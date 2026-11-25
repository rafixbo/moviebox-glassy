import 'package:flutter_test/flutter_test.dart';
import 'package:moviebox_glassy/api/models.dart';
import 'package:moviebox_glassy/api/moviebox_api.dart';

/// The header split between the manifest path (DASH/HLS, opened
/// directly with these headers — mpv sends them on every segment)
/// and the direct file path (mp4) is load-bearing: the bcdn CDN 429s
/// any mp4 request carrying the sportslive.wine Referer (verified
/// live 2026-11-23), while DASH hosts require the Cookie and accept
/// the Referer.
void main() {
  test('directFileHeaders sends UA only — no Referer, no Cookie', () {
    final headers = directFileHeaders();
    expect(headers['User-Agent'], kUserAgent);
    expect(headers, isNot(contains('Referer')));
    expect(headers, isNot(contains('Cookie')));
    expect(headers.length, 1);
  });

  test('streamHeaders (manifest path) keeps UA + Referer + Cookie', () {
    final source = StreamSource(
      url: 'https://sbcdn3.hakunaymatata.com/dash/x/index.mpd',
      label: '1080p',
      cookie: 'Edge-Cache-Cookie=urlprefix=abc:sign=def:t=123',
    );
    final headers = streamHeaders(source);
    expect(headers['User-Agent'], kUserAgent);
    expect(headers['Referer'], kPlayerReferer);
    expect(headers['Cookie'], contains('Edge-Cache-Cookie'));
  });

  test('streamHeaders without a cookie omits Cookie', () {
    final source = StreamSource(
      url: 'https://example.invalid/video.mp4',
      label: '720p',
    );
    final headers = streamHeaders(source);
    expect(headers, isNot(contains('Cookie')));
    expect(headers['Referer'], kPlayerReferer);
  });
}
