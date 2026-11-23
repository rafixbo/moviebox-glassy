import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../api/models.dart';
import '../api/moviebox_api.dart';

/// Local loopback relay for DASH (.mpd) and HLS (.m3u8) playback.
///
/// Why this exists: media_kit passes `httpHeaders` to mpv exactly
/// once, globally, at load time (`http-header-fields`). Whether mpv
/// re-applies those headers to every DASH `.m4s` segment fetch is
/// unverified — and the user reports playback stops after exactly one
/// 5 s segment and stutters, while a live probe (2026-11-23) proves
/// the CDN returns 200 for the manifest and every segment with the
/// session cookie, and ffmpeg decodes 180 s cleanly with the same
/// headers. That combination points at the player, not the CDN:
/// later segment fetches go out without the cookie and 403.
///
/// The relay takes the player out of header handling entirely. The
/// player opens a loopback manifest and the relay attaches UA +
/// Referer + Cookie to EVERY upstream request (manifest + every
/// segment), refreshing the cookie from the API on 403, without the
/// player ever restarting. Same architecture as MovieBox-Tui's
/// StreamRelay and AnyFilm's LocalMovieBoxServer.
///
/// URL scheme (mirrors TUI's `/https/<host>/<path>`): the manifest is
/// served at a loopback URL that mirrors the upstream path, e.g.
/// `http://127.0.0.1:PORT/https/sacdn.hakunaymatata.com/dash/.../
/// index_web.mpd`. The manifest is rewritten by pure prefix swap
/// (`https://<host>/` → loopback `/https/<host>/`), so DASH template
/// variables (`$RepresentationID$`, `$Number%05d$`) survive verbatim
/// and relative segment URLs resolve against the loopback manifest
/// URL automatically. Direct media files (.mp4/.mkv) do NOT go
/// through the relay — the signed `?sign=` mp4 links work with no
/// headers at all (proven live), so they keep the direct path.
class StreamRelay {
  StreamRelay({required this.refreshSource});

  /// Re-fetch a fresh source for the same title/episode (fresh
  /// cookie). Returns null when no fresh source is available.
  final Future<StreamSource?> Function() refreshSource;

  HttpServer? _server;
  HttpClient? _client;
  StreamSource? _source;
  Future<bool>? _refreshing;

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;

  bool get _isHls =>
      (_source?.url.split('?').first.toLowerCase().endsWith('.m3u8') ??
      false);

  /// Loopback URL the player opens instead of the raw manifest.
  /// Mirrors the upstream manifest path so relative segment URLs
  /// resolve through the relay automatically.
  String get manifestUrl {
    final uri = Uri.parse(_source!.url);
    final path = '/${uri.scheme}/${uri.host}'
        '${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return 'http://127.0.0.1:$port$path$query';
  }

  Future<void> start(StreamSource source) async {
    await stop();
    _source = source;
    _client = HttpClient()..autoUncompress = false;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
    _client?.close(force: true);
    _client = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method != 'GET') {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        await req.response.close();
        return;
      }
      // Route: /<scheme>/<host>[:port]/<path...>?<query>
      final segments = req.uri.pathSegments;
      if (segments.length < 2 ||
          (segments[0] != 'https' && segments[0] != 'http')) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      final upstream = Uri(
        scheme: segments[0],
        host: segments[1].split(':').first,
        port: segments[1].contains(':')
            ? int.tryParse(segments[1].split(':').last) ?? 0
            : 0,
        pathSegments: segments.sublist(2),
        query: req.uri.query.isEmpty ? null : req.uri.query,
      );
      final base = upstream.path.split('?').first.toLowerCase();
      if (base.endsWith('.mpd') || base.endsWith('.m3u8')) {
        await _serveManifest(req, upstream);
      } else {
        await _serveUpstream(req, upstream);
      }
    } catch (e) {
      try {
        req.response.statusCode = HttpStatus.badGateway;
        await req.response.close();
      } catch (_) {}
    }
  }

  /// Fetch the real manifest, rewrite its absolute URLs to loopback
  /// by prefix swap, and serve the rewritten manifest to the player.
  /// Relative URLs need no rewriting: they resolve against this
  /// loopback manifest URL, which mirrors the upstream path.
  Future<void> _serveManifest(HttpRequest req, Uri upstream) async {
    final res = await _fetchUpstream(upstream);
    if (res.statusCode != 200) {
      await res.drain<void>();
      req.response.statusCode = res.statusCode;
      await req.response.close();
      return;
    }
    final body = await res.transform(utf8.decoder).join();
    final rewritten = _rewriteManifest(body);
    final bytes = utf8.encode(rewritten);
    req.response.headers.contentType = _isHls
        ? ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8')
        : ContentType('application', 'dash+xml', charset: 'utf-8');
    req.response.headers.contentLength = bytes.length;
    req.response.add(bytes);
    await req.response.close();
  }

  /// Proxy one upstream media request (segment, init, key, ...),
  /// forwarding Range and streaming bytes back with 200/206.
  Future<void> _serveUpstream(HttpRequest req, Uri upstream) async {
    final range = req.headers.value(HttpHeaders.rangeHeader);
    final upstreamRes = await _fetchUpstream(upstream, range: range);
    req.response.statusCode = upstreamRes.statusCode;
    final ct = upstreamRes.headers.contentType;
    if (ct != null) req.response.headers.contentType = ct;
    final len = upstreamRes.headers.value(HttpHeaders.contentLengthHeader);
    if (len != null) {
      req.response.headers.set(HttpHeaders.contentLengthHeader, len);
    }
    final cr = upstreamRes.headers.value(HttpHeaders.contentRangeHeader);
    if (cr != null) {
      req.response.headers.set(HttpHeaders.contentRangeHeader, cr);
    }
    final ar = upstreamRes.headers.value(HttpHeaders.acceptRangesHeader);
    if (ar != null) {
      req.response.headers.set(HttpHeaders.acceptRangesHeader, ar);
    }
    await req.response.addStream(upstreamRes);
    await req.response.close();
  }

  /// Upstream GET with the stream headers; on 403, refresh the cookie
  /// once from the API and retry with the fresh headers.
  Future<HttpClientResponse> _fetchUpstream(
    Uri uri, {
    String? range,
  }) async {
    var res = await _get(uri, range: range);
    if (res.statusCode == 403) {
      final refreshed = await _refreshOnce();
      if (refreshed) {
        await res.drain<void>();
        res = await _get(uri, range: range);
      }
    }
    return res;
  }

  Future<HttpClientResponse> _get(Uri uri, {String? range}) async {
    final source = _source;
    final req = await _client!.getUrl(uri);
    if (source != null) {
      for (final e in streamHeaders(source).entries) {
        req.headers.set(e.key, e.value);
      }
    }
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    return req.close();
  }

  /// Swap in a fresh source (fresh cookie) at most once per failure
  /// burst; concurrent 403s share one refresh.
  Future<bool> _refreshOnce() {
    final pending = _refreshing;
    if (pending != null) return pending;
    final future = _doRefresh();
    _refreshing = future;
    return future.whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    try {
      final fresh = await refreshSource();
      if (fresh == null) return false;
      _source = fresh;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Prefix-swap every absolute `http(s)://<host>/...` URL in a
  /// manifest/playlist to the loopback mirror
  /// (`http://127.0.0.1:<port>/<scheme>/<host>/...`). Template
  /// variables (`$RepresentationID$`, `$Number%05d$`) and relative
  /// URLs are left untouched — the client substitutes/resolves them
  /// against the loopback manifest URL, which mirrors the upstream
  /// path, so they land back on this relay.
  String _rewriteManifest(String body) {
    return body.replaceAllMapped(
      RegExp('https?://([^/\\s"\'<>]+)(/[^\\s"\'<>]*)?'),
      (m) {
        final scheme = m.group(0)!.startsWith('https') ? 'https' : 'http';
        final host = m.group(1)!;
        final path = m.group(2) ?? '/';
        return 'http://127.0.0.1:$port/$scheme/$host$path';
      },
    );
  }
}
