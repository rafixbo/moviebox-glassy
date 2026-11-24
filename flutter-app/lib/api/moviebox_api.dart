import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'h5_api.dart';
import 'models.dart';

/// MovieBox API client — Dart port of mesamirh/MovieBox-Tui
/// (`src/providers/moviebox/{client,crypto,session}.rs`).
///
/// Hosts, endpoints and the request-signing scheme are replicated exactly
/// from that project (MIT/Apache). The app hosts no media; it is a
/// third-party client for personal use.

const String kPlayerReferer = 'https://sportslive.wine';

/// HTTP headers for DASH/HLS streams, mirroring the upstream
/// MovieBox-Tui adapter (`src/providers/moviebox/adapt.rs`):
/// `Referer` + `User-Agent`, PLUS the session `Cookie` when the source
/// carries one. The cookie is the decisive header for DASH (.mpd)
/// streams: the CDN returns 403 on the manifest and on every .m4s
/// segment without it (verified live 2026-11-23). These headers are
/// attached by the [StreamRelay] to EVERY upstream request (manifest +
/// every segment) — they are NOT passed to the player anymore, because
/// media_kit's one-time `httpHeaders` do not reliably reach later
/// DASH segment fetches.
Map<String, String> streamHeaders(StreamSource source) {
  final headers = <String, String>{
    'User-Agent': kUserAgent,
    'Referer': kPlayerReferer,
  };
  final cookie = source.cookie;
  if (cookie != null && cookie.isNotEmpty) {
    headers['Cookie'] = cookie;
  }
  return headers;
}

/// Headers for a DIRECT media file (.mp4/.mkv, or any non-manifest
/// source) opened by the player or the downloader: User-Agent only.
///
/// The bcdn CDN answers 429 ("Too Many Requests", plain nginx page)
/// to ANY mp4 request carrying `Referer: https://sportslive.wine` —
/// verified live 2026-11-23 (Interstellar 720p: UA + Range → 206,
/// Referer + Range → 429, UA + Referer + Range → 429; ffmpeg with
/// the app's old headers exits 8, UA-only exits 0). Since the mp4 is
/// the FIRST source for ~67/68 titles, this Referer was the reason
/// "many videos don't play". The signed `?sign=` URL is the auth for
/// these files, so no Cookie is needed either. Matches upstream
/// MovieBox-Tui (which strips Referer on direct MP4) and the official
/// app (which sends no Referer at all on its ExoPlayer path).
Map<String, String> directFileHeaders() => {'User-Agent': kUserAgent};
const String kUserAgent =
    'com.community.oneroom/50020120 (Linux; U; Android 13; en_US; 23078RKD5C; Build/TQ2A.230405.003; Cronet/135.0.7012.3)';

/// HMAC-MD5 secret from the upstream crypto module (hex).
const String _secretHex =
    'efa891974eecd3148df63aa611602defd101259ba521022c57ae0566bd8e';

/// Cert SHA-256 used for the x-client-build tag (upstream constant).
const String _certSha256 =
    '03d4b741632d136bc23e2de4c6adcdb7712f1980b619c183221801730bbd0410';

const List<String> _hosts = [
  'https://api6.aoneroom.com',
  'https://api5.aoneroom.com',
  'https://api4.aoneroom.com',
  'https://api4sg.aoneroom.com',
  'https://api3.aoneroom.com',
  'https://api6sg.aoneroom.com',
  'https://api.inmoviebox.com',
];

const List<int> _retryStatuses = [403, 406, 407, 429, 500, 502, 503, 504];

String _md5Hex(List<int> bytes) => md5.convert(bytes).toString();

String _randomHex(int len, [Random? rng]) {
  final r = rng ?? Random.secure();
  const chars = '0123456789abcdef';
  return List.generate(len, (_) => chars[r.nextInt(16)]).join();
}

/// Pure signing helpers — unit-tested in test/signing_test.dart.
class MovieBoxSigning {
  /// Canonical string: METHOD\naccept\ncontent-type\nbodyLen\nts\nbodyMd5\npath+sortedQuery
  static String canonical({
    required String method,
    required String url,
    required String? body,
    required int timestampMs,
  }) {
    final uri = Uri.parse(url);
    final pairs =
        uri.queryParametersAll.entries
            .expand((e) => e.value.map((v) => MapEntry(e.key, v)))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final query = pairs.map((e) => '${e.key}=${e.value}').join('&');
    final canonicalUrl = query.isEmpty ? uri.path : '${uri.path}?$query';
    final bodyBytes = body == null ? null : utf8.encode(body);
    final bodyHash = bodyBytes == null
        ? ''
        : _md5Hex(
            bodyBytes.length > 102400
                ? bodyBytes.sublist(0, 102400)
                : bodyBytes,
          );
    final bodyLen = bodyBytes == null ? '' : '${bodyBytes.length}';
    return '${method.toUpperCase()}\napplication/json\napplication/json\n$bodyLen\n$timestampMs\n$bodyHash\n$canonicalUrl';
  }

  /// "{ts}|2|{base64(HMAC-MD5(secret, canonical))}"
  static String trSignature({
    required String method,
    required String url,
    required String? body,
    required int timestampMs,
  }) {
    final canonicalStr = canonical(
      method: method,
      url: url,
      body: body,
      timestampMs: timestampMs,
    );
    final key = _hexToBytes(_secretHex);
    final mac = Hmac(md5, key).convert(utf8.encode(canonicalStr)).bytes;
    return '$timestampMs|2|${base64Encode(mac)}';
  }

  /// "{ts},{md5(reversed decimal ts)}"
  static String clientToken(int timestampMs) {
    final ts = timestampMs.toString();
    return '$ts,${_md5Hex(utf8.encode(ts.split('').reversed.join()))}';
  }

  /// stamp = "{tsSeconds}{millis:03d}000{rand 0-999}";
  /// build = "{stamp}.{md5(certHex + 'oneroom' + stamp)}"
  static String clientBuild(int timestampMs, [int? randPart]) {
    final rand = randPart ?? Random().nextInt(1000);
    final stamp =
        '${timestampMs ~/ 1000}'
        '${(timestampMs % 1000).toString().padLeft(3, '0')}000$rand';
    return '$stamp.${_md5Hex(utf8.encode('$_certSha256'
    'oneroom$stamp'))}';
  }

  static List<int> _hexToBytes(String hex) {
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}

class MovieBoxApi {
  MovieBoxApi._();
  static final MovieBoxApi instance = MovieBoxApi._();

  final http.Client _client = http.Client();
  String? _token;
  int? _tokenExp; // epoch seconds from the JWT
  int _lastGoodIdx = 0; // host index that worked last time (persisted)
  String? _deviceId;
  String? _gaid;
  bool _idsLoaded = false;

  /// Short per-host timeout: a dead or slow host must not stall the app.
  /// Worst case for a full sweep is ~10s (first host + parallel race),
  /// not 7 x 12s as before.
  static const Duration _hostTimeout = Duration(seconds: 5);

  /// Shown to the user when every host fails. Raw socket/DNS errors are
  /// logged only (debugPrint) and never surfaced to the UI.
  static const String kUnreachableMessage = 'Could not reach the server';

  Future<void> _ensureIds() async {
    if (_idsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('mb_device_id') ?? _randomHex(32);
    _gaid =
        prefs.getString('mb_gaid') ??
        '${_randomHex(8)}-${_randomHex(4)}-${_randomHex(4)}-${_randomHex(4)}-${_randomHex(12)}';
    await prefs.setString('mb_device_id', _deviceId!);
    await prefs.setString('mb_gaid', _gaid!);
    _token = prefs.getString('mb_token');
    final exp = prefs.getInt('mb_token_exp');
    if (exp != null) _tokenExp = exp;
    _lastGoodIdx = prefs.getInt('mb_last_good_host') ?? 0;
    if (_lastGoodIdx < 0 || _lastGoodIdx >= _hosts.length) _lastGoodIdx = 0;
    _idsLoaded = true;
  }

  Future<void> _saveLastGood(int idx) async {
    _lastGoodIdx = idx;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mb_last_good_host', idx);
  }

  bool get _tokenValid {
    if (_token == null || _token!.isEmpty) return false;
    if (_tokenExp != null) {
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60 < _tokenExp!;
    }
    return true;
  }

  /// Visitor login: POST /wefeed-mobile-bff/user-api/visitor-login {}
  Future<String> ensureSession() async {
    await _ensureIds();
    if (_tokenValid) return _token!;
    final json = await _requestRaw(
      'POST',
      '/wefeed-mobile-bff/user-api/visitor-login',
      body: '{}',
      withAuth: false,
    );
    final data = json['data'] is Map ? json['data'] as Map : json;
    final token = data['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw const MovieBoxException('Missing token from visitor-login');
    }
    _token = token;
    _tokenExp = _jwtExp(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mb_token', token);
    if (_tokenExp != null) await prefs.setInt('mb_token_exp', _tokenExp!);
    return token;
  }

  void invalidateSession() {
    _token = null;
    _tokenExp = null;
    SharedPreferences.getInstance().then((p) => p.remove('mb_token'));
  }

  static int? _jwtExp(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = jsonDecode(utf8.decode(base64Decode(payload))) as Map;
      final exp = decoded['exp'];
      if (exp is num) return exp.toInt();
      return int.tryParse(exp?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _signedHeaders({
    required String method,
    required String url,
    required String? body,
    String? token,
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final build = MovieBoxSigning.clientBuild(ts);
    final clientInfo = jsonEncode({
      'package_name': 'com.community.oneroom',
      'version_name': '4.0.01.0813.03',
      'version_code': 50020120,
      'os': 'android',
      'os_version': '13',
      'install_ch': 'ps',
      'device_id': _deviceId ?? '',
      'install_store': 'ps',
      'gaid': _gaid ?? '',
      'brand': 'Redmi',
      'model': '23078RKD5C',
      'system_language': 'en',
      'net': 'NETWORK_WIFI',
      'region': 'US',
      'timezone': 'Asia/Kolkata',
      'sp_code': '40401',
      'X-Play-Mode': '2',
      'X-Client-Build': build,
    });
    final headers = <String, String>{
      'User-Agent': kUserAgent,
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Connection': 'keep-alive',
      'x-client-token': MovieBoxSigning.clientToken(ts),
      'x-tr-signature': MovieBoxSigning.trSignature(
        method: method,
        url: url,
        body: body,
        timestampMs: ts,
      ),
      'x-client-build': build,
      'x-client-info': clientInfo,
      'x-client-status': '0',
      'x-forwarded-for': '103.241.12.34',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// One signed request against one host. Throws on any failure (DNS,
  /// timeout, retryable/non-2xx status, bad JSON) so the caller can move
  /// on to the next host.
  Future<Map<String, dynamic>> _attempt(
    String base,
    String method,
    String path, {
    String? body,
    String? token,
  }) async {
    final url = '$base$path';
    final resp =
        await (method == 'POST'
                ? _client.post(
                    Uri.parse(url),
                    headers: _signedHeaders(
                      method: method,
                      url: url,
                      body: body,
                      token: token,
                    ),
                    body: body,
                  )
                : _client.get(
                    Uri.parse(url),
                    headers: _signedHeaders(
                      method: method,
                      url: url,
                      body: null,
                      token: token,
                    ),
                  ))
            .timeout(_hostTimeout);
    if (_retryStatuses.contains(resp.statusCode) ||
        resp.statusCode < 200 ||
        resp.statusCode >= 300) {
      throw MovieBoxException('HTTP ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }

  /// Race several hosts in parallel; the first success wins and becomes
  /// the new last-known-good host. Throws the first error if all fail.
  /// Errors are swallowed per-attempt so no unhandled async errors escape
  /// once the race has a winner.
  Future<Map<String, dynamic>> _raceHosts(
    List<int> indices,
    String method,
    String path, {
    String? body,
    String? token,
  }) async {
    final completer = Completer<Map<String, dynamic>>();
    var failures = 0;
    Object? firstError;
    for (final idx in indices) {
      _attempt(_hosts[idx], method, path, body: body, token: token)
          .then((value) {
            if (!completer.isCompleted) {
              unawaited(_saveLastGood(idx));
              completer.complete(value);
            }
          })
          .catchError((Object e) {
            firstError ??= e;
            failures++;
            if (failures == indices.length && !completer.isCompleted) {
              completer.completeError(firstError!);
            }
            return null;
          });
    }
    return completer.future;
  }

  Future<Map<String, dynamic>> _requestRaw(
    String method,
    String path, {
    String? body,
    bool withAuth = true,
  }) async {
    await _ensureIds();
    final token = withAuth ? await ensureSession() : null;
    // Try the last-known-good host first (fast path when healthy),
    // then race the rest in parallel so one dead/slow host can't stall
    // the app. Host list is unchanged (upstream, Nov 2026, still live).
    final order = <int>[
      _lastGoodIdx,
      for (var i = 0; i < _hosts.length; i++)
        if (i != _lastGoodIdx) i,
    ];
    Object? lastError;
    try {
      return await _attempt(
        _hosts[order.first],
        method,
        path,
        body: body,
        token: token,
      );
    } catch (e) {
      lastError = e;
    }
    try {
      return await _raceHosts(
        order.sublist(1),
        method,
        path,
        body: body,
        token: token,
      );
    } catch (e) {
      lastError = e;
    }
    // Technical detail goes to the log only — the UI shows a short
    // friendly message. Auth failures (401/403) are rethrown as-is so the
    // session-refresh path in _request still sees them.
    debugPrint('[MovieBoxApi] all hosts failed for $path: $lastError');
    if (lastError is MovieBoxException &&
        (lastError.message.contains('401') ||
            lastError.message.contains('403'))) {
      throw lastError;
    }
    throw const MovieBoxException(kUnreachableMessage);
  }

  /// Request with one session refresh + retry on 401/403.
  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? body,
  }) async {
    try {
      return await _requestRaw(method, path, body: body);
    } on MovieBoxException catch (e) {
      if (e.message.contains('401') || e.message.contains('403')) {
        invalidateSession();
        return _requestRaw(method, path, body: body);
      }
      rethrow;
    }
  }

  // ---- Public API ----
  //
  // Home, search and details try the H5 (web) API first: it answers
  // through themoviebox.xyz, which loads on networks where the mobile
  // hosts (api*.aoneroom.com) fail DNS entirely. When H5 fails, the
  // mobile API is the fallback. Playback (streams/captions) stays on
  // the mobile API — H5 play returns no streams to guests.

  Future<List<Subject>> search(String query, {int page = 1}) async {
    try {
      return await H5Api.instance.search(query, page: page);
    } on H5Exception catch (e) {
      debugPrint('[MovieBoxApi] H5 search failed, trying mobile: $e');
    }
    final body = jsonEncode({
      'keyword': query,
      'page': page,
      'perPage': 15,
      'subjectType': 0,
    });
    final json = await _request(
      'POST',
      '/wefeed-mobile-bff/subject-api/search/v2',
      body: body,
    );
    return parseSearchResults(json);
  }

  Future<({List<Subject> hero, List<Subject> all})> homeFeed({
    int page = 1,
  }) async {
    try {
      return await H5Api.instance.homeFeed();
    } on H5Exception catch (e) {
      debugPrint('[MovieBoxApi] H5 home failed, trying mobile: $e');
    }
    final json = await _request(
      'GET',
      '/wefeed-mobile-bff/tab-operating?page=$page&tabId=2&version=',
    );
    return parseHomeFeed(json);
  }

  Future<Details> details(String subjectId, {String? detailPath}) async {
    if (detailPath != null && detailPath.isNotEmpty) {
      try {
        return await H5Api.instance.detailsByPath(detailPath);
      } on H5Exception catch (e) {
        debugPrint('[MovieBoxApi] H5 details failed, trying mobile: $e');
      }
    }
    final json = await _request(
      'GET',
      '/wefeed-mobile-bff/subject-api/get?subjectId=$subjectId',
    );
    final data = json['data'];
    final stype =
        (data is Map ? (data['subjectType'] ?? data['stype']) : null) ??
        json['subjectType'] ??
        1;
    final isSeries =
        (stype is num ? stype.toInt() : int.tryParse('$stype') ?? 1) == 2;
    Map<String, dynamic>? seasonJson;
    if (isSeries) {
      try {
        seasonJson = await _request(
          'GET',
          '/wefeed-mobile-bff/subject-api/season-info?subjectId=$subjectId',
        );
      } catch (_) {
        seasonJson = null; // seasons are best-effort; details still usable
      }
    }
    return Details.fromJson(json, seasonJson);
  }

  Future<List<CaptionTrack>> captions(
    String subjectId,
    String resourceId,
  ) async {
    try {
      final json = await _request(
        'GET',
        '/wefeed-mobile-bff/subject-api/get-ext-captions?subjectId=$subjectId&resourceId=$resourceId',
      );
      return parseCaptions(json);
    } catch (_) {
      return const []; // subtitles are best-effort
    }
  }

  Future<List<StreamSource>> streams(
    String subjectId, {
    int season = 0,
    int episode = 0,
    List<Map<String, dynamic>> detectors = const [],
  }) async {
    final seEp = (season == 0 && episode == 0) ? '' : '&se=$season&ep=$episode';
    Map<String, dynamic>? playInfo;
    Map<String, dynamic>? resource;
    try {
      playInfo = await _request(
        'GET',
        '/wefeed-mobile-bff/subject-api/play-info/v2?subjectId=$subjectId$seEp',
      );
    } catch (_) {
      playInfo = null;
    }
    try {
      resource = await _request(
        'GET',
        '/wefeed-mobile-bff/subject-api/resource?subjectId=$subjectId$seEp&page=1&perPage=20',
      );
    } catch (_) {
      resource = null;
    }
    var sources = parseStreamSources(
      playInfo: playInfo,
      resource: resource,
      detectors: detectors,
      season: season,
      episode: episode,
    );
    // Recover placeholder (upgrade-clip) links via resource-position.
    const placeholder =
        'https://macdn.aoneroom.com/other/2026/10/10/80da52722ee7de7a4303290af6783424.mp4';
    final recovered = <StreamSource>[];
    for (final s in sources) {
      recovered.add(s);
    }
    // parseStreamSources already drops the placeholder itself; the resource
    // list items that *only* had the placeholder are recovered here by
    // re-checking the raw resource list.
    final rData = resource?['data'];
    final list = (rData is Map ? rData['list'] : null) as List?;
    if (list != null) {
      for (final item in list) {
        if (item is! Map) continue;
        final link = (item['resourceLink'] ?? item['url'])?.toString() ?? '';
        if (link != placeholder) continue;
        final rid = (item['resourceId'] ?? item['id'])?.toString() ?? '';
        if (rid.isEmpty) continue;
        try {
          final pos = await _request(
            'GET',
            '/wefeed-mobile-bff/subject-api/resource-position/v2?subjectId=$subjectId&resourceId=$rid&failUrl=${Uri.encodeComponent(placeholder)}',
          );
          final posData = pos['data'];
          final posList = (posData is Map ? posData['list'] : null) as List?;
          if (posList != null) {
            for (final p in posList) {
              if (p is! Map) continue;
              if ((p['resourceId']?.toString() ?? '') != rid) continue;
              final url = (p['resourceLink'] ?? p['url'])?.toString();
              if (url == null || url.isEmpty || url == placeholder) continue;
              final res = p['resolution'] is num
                  ? (p['resolution'] as num).toInt()
                  : int.tryParse('${p['resolution']}') ?? 0;
              recovered.add(
                StreamSource(
                  url: url,
                  label: res > 0 ? '${res}p' : 'Direct',
                  resolution: res,
                  sizeBytes: p['size'] is num
                      ? (p['size'] as num).toInt()
                      : int.tryParse('${p['size']}'),
                  uploader: p['uploadBy']?.toString(),
                  resourceId: rid,
                  cookie: cleanSignCookie(p['signCookie']),
                ),
              );
            }
          }
        } catch (_) {
          // Recovery is best-effort.
        }
      }
    }
    // De-duplicate + sort highest quality first.
    final seen = <String>{};
    final deduped = <StreamSource>[];
    for (final s in [...sources, ...recovered]) {
      if (seen.add(s.url.split('?').first)) deduped.add(s);
    }
    deduped.sort((a, b) {
      final c = b.resolution.compareTo(a.resolution);
      return c != 0 ? c : (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0);
    });
    return deduped;
  }
}

class MovieBoxException implements Exception {
  final String message;
  const MovieBoxException(this.message);
  @override
  String toString() => 'MovieBoxException: $message';
}
