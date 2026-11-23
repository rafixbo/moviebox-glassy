import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moviebox_glassy/api/moviebox_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LIVE REGRESSION PROOF for the mp4 Referer 429 (2026-11-23).
///
/// Fetches a FRESH mp4 source from the API and Range-GETs it twice:
/// once with the headers the player now sends for direct files
/// ([directFileHeaders] — UA only) and once with the OLD headers
/// (UA + Referer). The bcdn CDN must answer 206 to the first and
/// 429 to the second — exactly the behaviour that made "many videos
/// don't play" (mp4 is the first source for ~67/68 titles).
///
/// Skipped by default (CI must stay offline-safe). Run manually:
///   LIVE_PROOF=1 flutter test test/mp4_headers_live_test.dart
void main() {
  test(
    'fresh mp4: UA-only returns 206, UA+Referer returns 429',
    () async {
      SharedPreferences.setMockInitialValues({});
      final subjects = await MovieBoxApi.instance.search('Interstellar');
      expect(subjects, isNotEmpty);
      final sources = await MovieBoxApi.instance.streams(subjects.first.id);
      final mp4 = sources.firstWhere(
        (s) => s.url.split('?').first.toLowerCase().endsWith('.mp4'),
        orElse: () => throw StateError('no mp4 source for Interstellar'),
      );

      Future<int> rangeStatus(Map<String, String> headers) async {
        final client = HttpClient();
        try {
          final req = await client
              .getUrl(Uri.parse(mp4.url))
              .timeout(const Duration(seconds: 30));
          req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
          for (final e in headers.entries) {
            req.headers.set(e.key, e.value);
          }
          final res = await req
              .close()
              .timeout(const Duration(seconds: 30));
          await res.drain<void>().timeout(const Duration(seconds: 30));
          return res.statusCode;
        } finally {
          client.close(force: true);
        }
      }

      expect(
        await rangeStatus(directFileHeaders()),
        206,
        reason: 'UA-only mp4 Range must be 206',
      );
      expect(
        await rangeStatus({
          'User-Agent': kUserAgent,
          'Referer': kPlayerReferer,
        }),
        429,
        reason: 'UA+Referer mp4 Range must be 429 (the old bug)',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: Platform.environment['LIVE_PROOF'] != '1'
        ? 'Set LIVE_PROOF=1 to run the live mp4 header proof'
        : false,
  );
}
