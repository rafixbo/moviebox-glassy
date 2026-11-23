import 'package:flutter_test/flutter_test.dart';
import 'package:moviebox_glassy/api/models.dart';
import 'package:moviebox_glassy/api/moviebox_api.dart';

/// Cookie tests — the DASH playback fix (2026-11-23).
///
/// Proven live: the CDN returns 403 on the DASH manifest and on every
/// .m4s segment unless the request carries the session `Cookie`
/// (`signCookie` from play-info). With it, ffprobe reads the stream
/// (hevc 1080/720/480 + aac) and ffmpeg decodes 5s cleanly; without
/// it, ffmpeg fails with 403. These tests pin the app-side contract:
/// the cookie is captured at parse time and sent on every playback
/// (and download) request.
void main() {
  test('cleanSignCookie drops empty parts and joins with "; "', () {
    expect(
      cleanSignCookie('Edge-Cache-Cookie=a:1; ; Foo=bar;'),
      'Edge-Cache-Cookie=a:1; Foo=bar',
    );
    expect(cleanSignCookie(''), isNull);
    expect(cleanSignCookie(null), isNull);
    expect(cleanSignCookie('  '), isNull);
    expect(
      cleanSignCookie('Edge-Cache-Cookie=urlprefix=abc:sign=def:t=123'),
      'Edge-Cache-Cookie=urlprefix=abc:sign=def:t=123',
    );
  });

  test('parseStreamSources captures signCookie from play-info streams', () {
    final sources = parseStreamSources(
      playInfo: {
        'data': {
          'streams': [
            {
              'url':
                  'https://sbcdn3.hakunaymatata.com/dash/x_1_2_1080_h265_144/index_web.mpd',
              'resolution': 1080,
              'codecName': 'hevc',
              'format': 'DASH',
              'signCookie': 'Edge-Cache-Cookie=urlprefix=abc:sign=def:t=123',
            },
            {
              'url': 'https://bcdn.hakunaymatata.com/resource/h265/x.mp4?sign=abc',
              'resolution': 360,
            },
          ],
        },
      },
      resource: null,
      detectors: const [],
      season: 1,
      episode: 2,
    );
    expect(sources.length, 2);
    expect(sources[0].resolution, 1080);
    expect(
      sources[0].cookie,
      'Edge-Cache-Cookie=urlprefix=abc:sign=def:t=123',
    );
    // Plain direct files carry no cookie (their ?sign= query is enough).
    expect(sources[1].cookie, isNull);
  });

  test('streamHeaders sends Cookie only when the source has one', () {
    final withCookie = streamHeaders(
      const StreamSource(
        url: 'https://example.test/index_web.mpd',
        label: '1080p',
        cookie: 'Edge-Cache-Cookie=x',
      ),
    );
    expect(withCookie['Cookie'], 'Edge-Cache-Cookie=x');
    expect(withCookie['Referer'], 'https://sportslive.wine');
    expect(withCookie['User-Agent'], isNotEmpty);

    final plain = streamHeaders(
      const StreamSource(url: 'https://example.test/x.mp4', label: 'Direct'),
    );
    expect(plain.containsKey('Cookie'), isFalse);
    expect(plain['Referer'], 'https://sportslive.wine');
  });
}
