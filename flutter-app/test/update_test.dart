import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moviebox_glassy/services/app_update.dart';

/// Update-gate tests: version.json parsing, build comparison, fail-open.
void main() {
  test('parses the shipped version.json shape', () {
    const raw = '''
{"latestVersion":"1.0.0","latestBuild":1,"minBuild":1,
 "apkUrl":"https://github.com/rafixbo/moviebox-glassy/releases/latest",
 "windowsUrl":"https://github.com/rafixbo/moviebox-glassy/releases/latest",
 "notes":"First release"}''';
    final info = UpdateInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    expect(info.latestVersion, '1.0.0');
    expect(info.latestBuild, 1);
    expect(info.minBuild, 1);
    expect(info.apkUrl, contains('github.com/rafixbo/moviebox-glassy'));
    expect(info.notes, 'First release');
  });

  test('compareBuilds: none / available / forced', () {
    const info = UpdateInfo(
      latestVersion: '1.1.0',
      latestBuild: 3,
      minBuild: 2,
      apkUrl: 'https://example.com/app.apk',
      windowsUrl: 'https://example.com/app.zip',
      notes: '',
    );
    expect(compareBuilds(installedBuild: 3, info: info), UpdateState.none);
    expect(compareBuilds(installedBuild: 4, info: info), UpdateState.none);
    expect(compareBuilds(installedBuild: 2, info: info), UpdateState.available);
    expect(compareBuilds(installedBuild: 1, info: info), UpdateState.forced);
    expect(compareBuilds(installedBuild: 0, info: info), UpdateState.forced);
  });

  test('bad version.json throws (caller must fail open)', () {
    expect(
      () => UpdateInfo.fromJson({'latestVersion': '1.0.0'}),
      throwsFormatException,
    );
  });

  test('check() fails open on unreachable host', () async {
    final client = MockClient((_) async => throw http.ClientException('offline'));
    final result = await AppUpdate.instance.check(client: client);
    expect(result, isNull);
  });

  test('check() fails open on non-200 and on bad JSON', () async {
    final notFound = MockClient((_) async => http.Response('nope', 404));
    expect(await AppUpdate.instance.check(client: notFound), isNull);

    final badJson = MockClient((_) async => http.Response('not json', 200));
    expect(await AppUpdate.instance.check(client: badJson), isNull);
  });

  test('check() returns available when remote build is newer', () async {
    // Installed build injected (1) so the test does not need PackageInfo /
    // platform channels; remote latestBuild 9999 / minBuild 9998 -> forced.
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'latestVersion': '9.9.9',
            'latestBuild': 9999,
            'minBuild': 9998,
            'apkUrl': 'https://example.com/app.apk',
            'windowsUrl': 'https://example.com/app.zip',
            'notes': 'future',
          }),
          200,
        ));
    final result = await AppUpdate.instance.check(
      client: client,
      installedBuildOverride: 1,
    );
    expect(result, isNotNull);
    expect(result!.state, UpdateState.forced);
    expect(result.info.latestVersion, '9.9.9');
  });

  test('check() returns available (not forced) when above minBuild', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'latestVersion': '9.9.9',
            'latestBuild': 9999,
            'minBuild': 1,
            'apkUrl': 'https://example.com/app.apk',
            'windowsUrl': 'https://example.com/app.zip',
            'notes': 'future',
          }),
          200,
        ));
    final result = await AppUpdate.instance.check(
      client: client,
      installedBuildOverride: 5,
    );
    expect(result, isNotNull);
    expect(result!.state, UpdateState.available);
  });

  test('check() returns null when installed build is current', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'latestVersion': '1.0.0',
            'latestBuild': 1,
            'minBuild': 1,
            'apkUrl': 'https://example.com/app.apk',
            'windowsUrl': 'https://example.com/app.zip',
            'notes': 'First release',
          }),
          200,
        ));
    final result = await AppUpdate.instance.check(
      client: client,
      installedBuildOverride: 1,
    );
    expect(result, isNull);
  });
}
