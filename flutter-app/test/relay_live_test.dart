import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moviebox_glassy/api/moviebox_api.dart';
import 'package:moviebox_glassy/services/stream_relay.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LIVE PROOF for the loopback relay (StreamRelay).
///
/// Boots the real relay with a REAL fresh source from the MovieBox
/// API, then decodes 90 s through the loopback manifest URL with
/// ffmpeg — with NO player headers at all, exactly what mpv will do
/// in the app. If this passes, the relay path is proven end to end:
/// manifest + segments served with the cookie attached server-side.
///
/// Skipped by default (CI must stay offline-safe). Run manually:
///   LIVE_PROOF=1 flutter test test/relay_live_test.dart
void main() {
  test(
    'relay serves a fresh DASH stream decodable for 90 s',
    () async {
      SharedPreferences.setMockInitialValues({});
      final sources = await MovieBoxApi.instance.streams(
        '5082782667922359744',
        season: 1,
        episode: 2,
      );
      final dash = sources.firstWhere(
        (s) => s.url.split('?').first.toLowerCase().endsWith('.mpd'),
        orElse: () => throw StateError('no DASH source in play-info'),
      );
      expect(dash.cookie, isNotNull, reason: 'play-info must carry a cookie');

      final relay = StreamRelay(
        refreshSource: () async {
          final fresh = await MovieBoxApi.instance.streams(
            '5082782667922359744',
            season: 1,
            episode: 2,
          );
          final base = dash.url.split('?').first;
          return fresh.firstWhere(
            (s) => s.url.split('?').first == base,
            orElse: () => fresh.first,
          );
        },
      );
      await relay.start(dash);
      try {
        // Sanity: the relayed manifest is reachable and rewritten.
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse(relay.manifestUrl));
        final res = await req.close();
        expect(res.statusCode, 200);
        final body = await res.transform(utf8.decoder).join();
        expect(body, contains('127.0.0.1'));
        client.close();

        // The proof: ffmpeg decodes 90 s through the loopback URL.
        final result = await Process.run('ffmpeg', [
          '-hide_banner',
          '-i',
          relay.manifestUrl,
          '-t',
          '90',
          '-f',
          'null',
          '-',
        ]);
        final stderr = result.stderr as String;
        final frames = RegExp(
          r'frame=\s*(\d+)',
        ).allMatches(stderr).map((m) => int.parse(m.group(1)!));
        final lastFrame = frames.isEmpty ? 0 : frames.last;
        expect(
          result.exitCode,
          0,
          reason: 'ffmpeg failed via relay: $stderr',
        );
        expect(
          lastFrame,
          greaterThan(1000),
          reason: 'expected >1000 frames in 90 s, got $lastFrame: $stderr',
        );
      } finally {
        await relay.stop();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: Platform.environment['LIVE_PROOF'] != '1'
        ? 'Set LIVE_PROOF=1 to run the live relay proof'
        : false,
  );
}
