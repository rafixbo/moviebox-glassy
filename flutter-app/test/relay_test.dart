import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moviebox_glassy/api/models.dart';
import 'package:moviebox_glassy/services/stream_relay.dart';

/// Unit tests for [StreamRelay] against a fake upstream CDN running on
/// loopback. The fake CDN requires `Cookie: test-cookie` (or
/// `fresh-cookie` after a refresh) and 403s anything else — the same
/// contract the real CDN enforces with the session cookie.
///
/// The manifest fixture uses real DASH SegmentTemplate variables
/// (`$RepresentationID$`, `$Number%05d$`): the relay must NOT resolve
/// them — the player substitutes them, and the substituted URL must
/// still land on the relay via the mirrored loopback path.
void main() {
  late HttpServer upstream;
  late int upstreamPort;
  final seenCookies = <String>[];
  var refreshCalls = 0;

  String manifestBody() => '''<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" mediaPresentationDuration="PT22M52.5S" minBufferTime="PT10.1S" type="static">
  <Period>
    <AdaptationSet mimeType="video/mp4" contentType="video">
      <Representation id="0" bandwidth="745000" width="1920" height="1080" codecs="hev1.1.6.L120.90">
        <SegmentTemplate timescale="1000000" duration="5000000" initialization="init-stream\$RepresentationID\$.m4s" media="chunk-stream\$RepresentationID\$-\$Number%05d\$.m4s" startNumber="1"/>
      </Representation>
      <Representation id="1" bandwidth="400000" width="1280" height="720">
        <SegmentTemplate timescale="1000000" duration="5000000" initialization="http://127.0.0.1:$upstreamPort/video/init-stream1.m4s" media="http://127.0.0.1:$upstreamPort/video/chunk-stream1-\$Number%05d\$.m4s" startNumber="1"/>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>
''';

  const hlsBody = '''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:5
#EXTINF:5.0,
seg-00001.ts
#EXTINF:5.0,
https://cdn.example.invalid/hls/seg-00002.ts
#EXT-X-ENDLIST
''';

  final segmentBytes = List<int>.generate(256, (i) => i % 256);

  Future<void> handleUpstream(HttpRequest req) async {
    final cookie = req.headers.value(HttpHeaders.cookieHeader) ?? '';
    seenCookies.add(cookie);
    final authorized =
        cookie.contains('test-cookie') || cookie.contains('fresh-cookie');
    if (!authorized) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }
    final path = req.uri.path;
    if (path == '/video/index.mpd') {
      final bytes = utf8.encode(manifestBody());
      req.response.headers.contentType = ContentType(
        'application',
        'dash+xml',
        charset: 'utf-8',
      );
      req.response.headers.contentLength = bytes.length;
      req.response.add(bytes);
      await req.response.close();
      return;
    }
    if (path == '/video/list.m3u8') {
      final bytes = utf8.encode(hlsBody);
      req.response.headers.contentType = ContentType(
        'application',
        'vnd.apple.mpegurl',
        charset: 'utf-8',
      );
      req.response.headers.contentLength = bytes.length;
      req.response.add(bytes);
      await req.response.close();
      return;
    }
    if (path.startsWith('/video/') || path.startsWith('/hls/')) {
      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range);
        if (m != null) {
          final start = int.parse(m.group(1)!);
          final end = int.parse(m.group(2)!);
          final slice = segmentBytes.sublist(start, end + 1);
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${segmentBytes.length}',
          );
          req.response.headers.contentLength = slice.length;
          req.response.add(slice);
          await req.response.close();
          return;
        }
      }
      req.response.headers.contentType = ContentType.binary;
      req.response.headers.contentLength = segmentBytes.length;
      req.response.add(segmentBytes);
      await req.response.close();
      return;
    }
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  setUp(() async {
    seenCookies.clear();
    refreshCalls = 0;
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstreamPort = upstream.port;
    upstream.listen(handleUpstream);
  });

  tearDown(() async {
    await upstream.close(force: true);
  });

  Future<(int, String)> getText(HttpClient client, String url) async {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return (res.statusCode, body);
  }

  Future<List<int>> getBytes(HttpClient client, String url) async {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    expect(res.statusCode, 200);
    return res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
  }

  StreamSource dashSource({String cookie = 'test-cookie'}) => StreamSource(
    url: 'http://127.0.0.1:$upstreamPort/video/index.mpd',
    label: '1080p',
    resolution: 1080,
    cookie: cookie,
  );

  test('relay serves the manifest at the mirrored loopback path', () async {
    final relay = StreamRelay(refreshSource: () async => null);
    await relay.start(dashSource());
    try {
      expect(
        relay.manifestUrl,
        'http://127.0.0.1:${relay.port}/http/127.0.0.1:$upstreamPort/video/index.mpd',
      );
      final client = HttpClient();
      final (status, body) = await getText(client, relay.manifestUrl);
      expect(status, 200);
      // Absolute upstream URLs prefix-swapped to loopback.
      expect(
        body,
        contains(
          'http://127.0.0.1:${relay.port}/http/127.0.0.1:$upstreamPort/video/init-stream1.m4s',
        ),
      );
      expect(
        body,
        isNot(contains('http://127.0.0.1:$upstreamPort/video/')),
      );
      // Template variables survive verbatim — the player substitutes
      // them, and the substituted URL resolves against this loopback
      // manifest URL back onto the relay.
      expect(body, contains(r'init-stream$RepresentationID$.m4s'));
      expect(body, contains(r'chunk-stream$RepresentationID$-$Number%05d$.m4s'));
      client.close();
    } finally {
      await relay.stop();
    }
  });

  test('relay attaches the cookie to template-substituted segments', () async {
    final relay = StreamRelay(refreshSource: () async => null);
    await relay.start(dashSource());
    try {
      final client = HttpClient();
      // Simulate the DASH client: substitute the template, resolve
      // against the loopback manifest URL.
      final manifestUri = Uri.parse(relay.manifestUrl);
      final segmentUri = manifestUri.resolve(
        'chunk-stream0-00001.m4s',
      );
      expect(
        segmentUri.toString(),
        startsWith('http://127.0.0.1:${relay.port}/http/'),
      );
      final bytes = await getBytes(client, segmentUri.toString());
      expect(bytes, segmentBytes);
      expect(seenCookies, contains('test-cookie'));
      client.close();
    } finally {
      await relay.stop();
    }
  });

  test('relay forwards Range and returns 206', () async {
    final relay = StreamRelay(refreshSource: () async => null);
    await relay.start(dashSource());
    try {
      final client = HttpClient();
      final segmentUrl =
          'http://127.0.0.1:${relay.port}/http/127.0.0.1:$upstreamPort/video/chunk-stream0-00001.m4s';
      final req = await client.getUrl(Uri.parse(segmentUrl));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
      final res = await req.close();
      final bytes = await res.fold<List<int>>(
        <int>[],
        (a, b) => a..addAll(b),
      );
      expect(res.statusCode, 206);
      expect(
        res.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 0-3/256',
      );
      expect(bytes, [0, 1, 2, 3]);
      client.close();
    } finally {
      await relay.stop();
    }
  });

  test('relay refreshes the cookie on 403 and retries', () async {
    final relay = StreamRelay(
      refreshSource: () async {
        refreshCalls++;
        return dashSource(cookie: 'fresh-cookie');
      },
    );
    await relay.start(dashSource(cookie: 'stale-cookie'));
    try {
      final client = HttpClient();
      final (status, body) = await getText(client, relay.manifestUrl);
      expect(status, 200);
      expect(body, contains(r'init-stream$RepresentationID$.m4s'));
      expect(refreshCalls, 1);
      expect(seenCookies, contains('stale-cookie'));
      expect(seenCookies, contains('fresh-cookie'));
      client.close();
    } finally {
      await relay.stop();
    }
  });

  test('relay rewrites HLS absolute URLs; relative lines resolve', () async {
    final relay = StreamRelay(refreshSource: () async => null);
    final source = StreamSource(
      url: 'http://127.0.0.1:$upstreamPort/video/list.m3u8',
      label: 'HLS',
      cookie: 'test-cookie',
    );
    await relay.start(source);
    try {
      final client = HttpClient();
      final (status, body) = await getText(client, relay.manifestUrl);
      expect(status, 200);
      // Absolute line prefix-swapped to loopback.
      expect(
        body,
        contains(
          'http://127.0.0.1:${relay.port}/https/cdn.example.invalid/hls/seg-00002.ts',
        ),
      );
      expect(body, isNot(contains('https://cdn.example.invalid')));
      // Relative line stays bare — it resolves against the loopback
      // playlist URL, which mirrors the upstream path.
      expect(body, contains('\nseg-00001.ts\n'));
      // And the resolved relative segment fetches through the relay.
      final playlistUri = Uri.parse(relay.manifestUrl);
      final bytes = await getBytes(
        client,
        playlistUri.resolve('seg-00001.ts').toString(),
      );
      expect(bytes, segmentBytes);
      client.close();
    } finally {
      await relay.stop();
    }
  });

  test('relay without a cookie surfaces the upstream 403', () async {
    final relay = StreamRelay(refreshSource: () async => null);
    await relay.start(dashSource(cookie: ''));
    try {
      final client = HttpClient();
      final (status, _) = await getText(client, relay.manifestUrl);
      expect(status, 403);
      client.close();
    } finally {
      await relay.stop();
    }
  });
}
