import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Remote in-app update check (version gate).
///
/// Source of truth:
/// https://raw.githubusercontent.com/rafixbo/moviebox-glassy/main/version.json
/// {"latestVersion":"1.0.0","latestBuild":1,"minBuild":1,
///  "apkUrl":"...","windowsUrl":"...","notes":"..."}
///
/// Fail-open by design: unreachable network, bad JSON, or missing fields
/// means "no update" — the app must never be blocked by a failed check.
class UpdateInfo {
  final String latestVersion;
  final int latestBuild;
  final int minBuild;
  final String apkUrl;
  final String windowsUrl;
  final String notes;

  const UpdateInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.minBuild,
    required this.apkUrl,
    required this.windowsUrl,
    required this.notes,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> j) {
    final latestBuild = j['latestBuild'];
    final minBuild = j['minBuild'];
    if (latestBuild is! num || minBuild is! num) {
      throw const FormatException('version.json missing latestBuild/minBuild');
    }
    return UpdateInfo(
      latestVersion: (j['latestVersion'] ?? '').toString(),
      latestBuild: latestBuild.toInt(),
      minBuild: minBuild.toInt(),
      apkUrl: (j['apkUrl'] ?? '').toString(),
      windowsUrl: (j['windowsUrl'] ?? '').toString(),
      notes: (j['notes'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'latestVersion': latestVersion,
        'latestBuild': latestBuild,
        'minBuild': minBuild,
        'apkUrl': apkUrl,
        'windowsUrl': windowsUrl,
        'notes': notes,
      };
}

enum UpdateState { none, available, forced }

/// Pure comparison — unit-tested in test/update_test.dart.
UpdateState compareBuilds({
  required int installedBuild,
  required UpdateInfo info,
}) {
  if (installedBuild < info.minBuild) return UpdateState.forced;
  if (installedBuild < info.latestBuild) return UpdateState.available;
  return UpdateState.none;
}

class AppUpdate {
  AppUpdate._();
  static final AppUpdate instance = AppUpdate._();

  static const versionUrl =
      'https://raw.githubusercontent.com/rafixbo/moviebox-glassy/main/version.json';

  /// Returns null when there is no update OR the check failed (fail-open).
  /// [installedBuildOverride] exists so tests can inject a build number
  /// without PackageInfo / platform channels.
  Future<({UpdateInfo info, UpdateState state})?> check({
    http.Client? client,
    String? versionUrlOverride,
    int? installedBuildOverride,
  }) async {
    try {
      final httpClient = client ?? http.Client();
      final resp = await httpClient
          .get(Uri.parse(versionUrlOverride ?? versionUrl))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final info = UpdateInfo.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
      final installed = installedBuildOverride ??
          int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ??
          0;
      final state = compareBuilds(installedBuild: installed, info: info);
      if (state == UpdateState.none) return null;
      return (info: info, state: state);
    } catch (e) {
      debugPrint('Update check failed (fail-open): $e');
      return null;
    }
  }
}
