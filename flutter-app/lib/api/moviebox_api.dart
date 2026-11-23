import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// MovieBox API client — Dart port of mesamirh/MovieBox-Tui
/// (`src/providers/moviebox/{client,crypto,session}.rs`).
///
/// Hosts, endpoints and the request-signing scheme are replicated exactly
/// from that project (MIT/Apache). The app hosts no media; it is a
/// third-party client for personal use.

const String kPlayerReferer = 'https://sportslive.wine';
const String kUserAgent =
    'com.community.oneroom/50020120 (Linux; U; Android 13; en_US; 23078RKD5C; Build/TQ2A.230405.003; Cronet/135.0.7012.3)';

/// HMAC-MD5 secret from the upstream crypto module (hex).
const String _secretHex = 'efa891974eecd3148df63aa611602defd101259ba521022c57ae0566bd8e';

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
    final pairs = uri.queryParametersAll.entries
        .expand((e) => e.value.map((v) => MapEntry(e.key, v)))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final query = pairs.map((e) => '${e.key}=${e.value}').join('&');
    final canonicalUrl = query.isEmpty ? uri.path : '${uri.path}?$query';
    final bodyBytes = body == null ? null : utf8.encode(body);
    final bodyHash = bodyBytes == null
        ? ''
        : _md5Hex(bodyBytes.length > 102400 ? bodyBytes.sublist(0, 102400) : bodyBytes);
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
        method: method, url: url, body: body, timestampMs: timestampMs);
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
    final stamp = '${timestampMs ~/ 1000}'
        '${(timestampMs % 1000).toString().padLeft(3, '0')}000$rand';
    return '$stamp.${_md5Hex(utf8.encode('$_certSha256' 'oneroom$stamp'))}';
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
  int _activeHost = 0;
  String? _deviceId;
  String? _gaid;
  bool _idsLoaded = false;

  Future<void> _ensureIds() async {
    if (_idsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('mb_device_id') ?? _randomHex(32);
    _gaid = prefs.getString('mb_gaid') ??
        '${_randomHex(8)}-${_randomHex(4)}-${_randomHex(4)}-${_randomHex(4)}-${_randomHex(12)}';
    await prefs.setString('mb_device_id', _deviceId!);
    await prefs.setString('mb_gaid', _gaid!);
    _token = prefs.getString('mb_token');
    final exp = prefs.getInt('mb_token_exp');
    if (exp != null) _tokenExp = exp;
    _idsLoaded = true;
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
    if (token.isEmpty) throw const MovieBoxException('Missing token from visitor-login');
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
          method: method, url: url, body: body, timestampMs: ts),
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

  Future<Map<String, dynamic>> _requestRaw(
    String method,
    String path, {
    String? body,
    bool withAuth = true,
  }) async {
    await _ensureIds();
    final token = withAuth ? await ensureSession() : null;
    Object? lastError;
    for (var i = 0; i < _hosts.length; i++) {
      final idx = (_activeHost + i) % _hosts.length;
      final base = _hosts[idx];
      final url = '$base$path';
      try {
        final resp = await (method == 'POST'
                ? _client.post(Uri.parse(url),
                    headers: _signedHeaders(method: method, url: url, body: body, token: token),
                    body: body)
                : _client.get(Uri.parse(url),
                    headers: _signedHeaders(method: method, url: url, body: null, token: token)))
            .timeout(const Duration(seconds: 12));
        if (_retryStatuses.contains(resp.statusCode)) {
          _activeHost = (idx + 1) % _hosts.length;
          lastError = MovieBoxException('HTTP ${resp.statusCode}');
          if (resp.statusCode == 429) {
            await Future.delayed(const Duration(milliseconds: 400));
          }
          continue;
        }
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw MovieBoxException('HTTP ${resp.statusCode}');
        }
        _activeHost = idx;
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) return decoded;
        return {'data': decoded};
      } catch (e) {
        lastError = e;
        _activeHost = (idx + 1) % _hosts.length;
        continue;
      }
    }
    throw lastError is Exception
        ? lastError
        : const MovieBoxException('All hosts exhausted');
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

  Future<List<Subject>> search(String query, {int page = 1}) async {
    final body = jsonEncode({
      'keyword': query,
      'page': page,
      'perPage': 15,
      'subjectType': 0,
    });
    final json = await _request('POST', '/wefeed-mobile-bff/subject-api/search/v2', body: body);
    return parseSearchResults(json);
  }

  Future<({List<Subject> hero, List<Subject> all})> homeFeed({int page = 1}) async {
    final json =
        await _request('GET', '/wefeed-mobile-bff/tab-operating?page=$page&tabId=2&version=');
    return parseHomeFeed(json);
  }

  Future<Details> details(String subjectId) async {
    final json = await _request(
        'GET', '/wefeed-mobile-bff/subject-api/get?subjectId=$subjectId');
    final data = json['data'];
    final stype = (data is Map ? (data['subjectType'] ?? data['stype']) : null) ??
        json['subjectType'] ??
        1;
    final isSeries = (stype is num ? stype.toInt() : int.tryParse('$stype') ?? 1) == 2;
    Map<String, dynamic>? seasonJson;
    if (isSeries) {
      try {
        seasonJson = await _request('GET',
            '/wefeed-mobile-bff/subject-api/season-info?subjectId=$subjectId');
      } catch (_) {
        seasonJson = null; // seasons are best-effort; details still usable
      }
    }
    return Details.fromJson(json, seasonJson);
  }

  Future<List<CaptionTrack>> captions(String subjectId, String resourceId) async {
    try {
      final json = await _request('GET',
          '/wefeed-mobile-bff/subject-api/get-ext-captions?subjectId=$subjectId&resourceId=$resourceId');
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
    final seEp = (season == 0 && episode == 0)
        ? ''
        : '&se=$season&ep=$episode';
    Map<String, dynamic>? playInfo;
    Map<String, dynamic>? resource;
    try {
      playInfo = await _request('GET',
          '/wefeed-mobile-bff/subject-api/play-info/v2?subjectId=$subjectId$seEp');
    } catch (_) {
      playInfo = null;
    }
    try {
      resource = await _request('GET',
          '/wefeed-mobile-bff/subject-api/resource?subjectId=$subjectId$seEp&page=1&perPage=20');
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
          final pos = await _request('GET',
              '/wefeed-mobile-bff/subject-api/resource-position/v2?subjectId=$subjectId&resourceId=$rid&failUrl=${Uri.encodeComponent(placeholder)}');
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
              recovered.add(StreamSource(
                url: url,
                label: res > 0 ? '${res}p' : 'Direct',
                resolution: res,
                sizeBytes: p['size'] is num
                    ? (p['size'] as num).toInt()
                    : int.tryParse('${p['size']}'),
                uploader: p['uploadBy']?.toString(),
                resourceId: rid,
              ));
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
