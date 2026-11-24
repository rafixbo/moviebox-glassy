import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// H5 (web) MovieBox API client — the same backend the official website
/// (themoviebox.xyz) uses, scraped from its Nuxt bundle and verified
/// live 2026-11-24.
///
/// Why this exists: the mobile hosts (`api*.aoneroom.com`) are
/// unreachable from some networks (DNS fails on Rafi's phone for all 7),
/// which left the app showing "Couldn't reach the server" on home.
/// The H5 API answers on TWO hosts:
///   1. `https://themoviebox.xyz` — the site itself proxies the BFF
///      (`/wefeed-h5api-bff/...`), so it works wherever the website
///      loads. Tried FIRST.
///   2. `https://h5-api.aoneroom.com` — the direct BFF host (the web
///      client's own `clientFetch.baseUrl`). Fallback.
///
/// Auth is a guest JWT, NOT the mobile visitor-login and NOT the
/// `X-Client-Token` (the web BFF does not sign requests — proven: the
/// token alone, the cookie alone, and both together all still 400'd
/// until the right Bearer token was sent):
///   GET `/wefeed-h5api-bff/country-code` -> read the `x-user`
///   response header -> JSON `{"token": <guest JWT>, ...}` -> send as
///   `Authorization: Bearer <token>` on every later call. The token
///   lives ~7 days; it is cached and refreshed on a 400 "invalid
///   token" (one retry).
///
/// Proven live 2026-11-24: home (10 platformList + 36 operatingList),
/// search (`data.items`, 154 hits for "avengers"), detail (subject +
/// seasons + resolutions) — code 0 on BOTH hosts with the same token.
/// Known limit: `/subject/play` returns code 0 but EMPTY streams/dash/
/// hls for guests, so playback still uses the mobile play-info /
/// resource endpoints (see [MovieBoxApi.streams]).
class H5Exception implements Exception {
  final String message;
  const H5Exception(this.message);
  @override
  String toString() => 'H5Exception: $message';
}

class H5Api {
  H5Api._();
  static final H5Api instance = H5Api._();

  final http.Client _client = http.Client();

  static const List<String> _hosts = [
    'https://themoviebox.xyz',
    'https://h5-api.aoneroom.com',
  ];

  /// Chrome UA: the probes that proved these endpoints used one, and
  /// the web header set documents a real browser UA.
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  static const Duration _hostTimeout = Duration(seconds: 5);

  /// Guest tokens live ~7 days; refresh well before expiry.
  static const Duration _tokenTtl = Duration(days: 6);

  String? _token;
  DateTime? _tokenFetchedAt;
  int _lastGoodIdx = 0;
  bool _prefsLoaded = false;

  Future<void> _ensurePrefs() async {
    if (_prefsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('mb_h5_token');
    final fetchedMs = prefs.getInt('mb_h5_token_at');
    if (fetchedMs != null) {
      _tokenFetchedAt = DateTime.fromMillisecondsSinceEpoch(fetchedMs);
    }
    _lastGoodIdx = prefs.getInt('mb_h5_last_good') ?? 0;
    if (_lastGoodIdx < 0 || _lastGoodIdx >= _hosts.length) _lastGoodIdx = 0;
    _prefsLoaded = true;
  }

  bool get _tokenValid {
    if (_token == null || _token!.isEmpty || _tokenFetchedAt == null) {
      return false;
    }
    return DateTime.now().difference(_tokenFetchedAt!) < _tokenTtl;
  }

  Future<void> _saveToken(String token) async {
    _token = token;
    _tokenFetchedAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mb_h5_token', token);
    await prefs.setInt(
      'mb_h5_token_at',
      _tokenFetchedAt!.millisecondsSinceEpoch,
    );
  }

  Future<void> _saveLastGood(int idx) async {
    _lastGoodIdx = idx;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mb_h5_last_good', idx);
  }

  void _dropToken() {
    _token = null;
    _tokenFetchedAt = null;
    SharedPreferences.getInstance().then((p) {
      p.remove('mb_h5_token');
      p.remove('mb_h5_token_at');
    });
  }

  Map<String, String> _headers() => {
    'User-Agent': _userAgent,
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'X-Client-Info': jsonEncode({'timezone': 'UTC'}),
    'X-Request-Lang': 'en',
    'x-no-high-risk-restrict': '0',
    'x-vip-restrict': '0',
    'x-source': '',
    'Referer': 'https://themoviebox.xyz/',
    if (_token != null && _token!.isNotEmpty)
      'Authorization': 'Bearer $_token',
  };

  /// One raw request against one host. Returns the decoded JSON map
  /// plus the response headers (the caller needs `x-user` for the
  /// guest token). Throws [H5Exception] on any failure.
  Future<({Map<String, dynamic> json, Map<String, String> headers})>
  _attempt(
    String base,
    String method,
    String path, {
    String? body,
  }) async {
    final url = '$base$path';
    final resp =
        await (method == 'POST'
                ? _client.post(
                    Uri.parse(url),
                    headers: _headers(),
                    body: body,
                  )
                : _client.get(Uri.parse(url), headers: _headers()))
            .timeout(_hostTimeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw H5Exception('HTTP ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw const H5Exception('Unexpected response');
    }
    return (json: decoded, headers: resp.headers);
  }

  /// Mint a fresh guest token from `country-code`'s `x-user` header.
  /// Tries the last-known-good host first, then the other one.
  Future<String> _mintGuestToken() async {
    await _ensurePrefs();
    final order = <int>[
      _lastGoodIdx,
      for (var i = 0; i < _hosts.length; i++)
        if (i != _lastGoodIdx) i,
    ];
    Object? lastError;
    for (final idx in order) {
      try {
        final res = await _attempt(
          _hosts[idx],
          'GET',
          '/wefeed-h5api-bff/country-code',
        );
        final xUser = res.headers['x-user'];
        if (xUser == null || xUser.isEmpty) {
          throw const H5Exception('No x-user header');
        }
        final parsed = jsonDecode(xUser);
        final token = (parsed is Map ? parsed['token'] : null)?.toString();
        if (token == null || token.isEmpty) {
          throw const H5Exception('No token in x-user');
        }
        unawaited(_saveLastGood(idx));
        await _saveToken(token);
        return token;
      } catch (e) {
        lastError = e;
      }
    }
    debugPrint('[H5Api] country-code failed on all hosts: $lastError');
    throw const H5Exception('Could not reach the server');
  }

  Future<String> _ensureGuestToken() async {
    await _ensurePrefs();
    if (_tokenValid) return _token!;
    return _mintGuestToken();
  }

  /// Request with one guest-token refresh + retry on 400 "invalid
  /// token". Tries the last-known-good host first, then the other.
  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? body,
  }) async {
    await _ensureGuestToken();
    final order = <int>[
      _lastGoodIdx,
      for (var i = 0; i < _hosts.length; i++)
        if (i != _lastGoodIdx) i,
    ];
    Future<Map<String, dynamic>> tryOnce() async {
      Object? lastError;
      for (final idx in order) {
        try {
          final res = await _attempt(
            _hosts[idx],
            method,
            path,
            body: body,
          );
          unawaited(_saveLastGood(idx));
          return res.json;
        } catch (e) {
          lastError = e;
        }
      }
      throw lastError ?? const H5Exception('Could not reach the server');
    }

    try {
      final json = await tryOnce();
      if (json['code'] == 400 && '${json['message']}'.contains('token')) {
        // Stale guest token: mint a fresh one and retry once.
        _dropToken();
        await _ensureGuestToken();
        return await tryOnce();
      }
      return json;
    } on H5Exception {
      rethrow;
    } catch (e) {
      debugPrint('[H5Api] request failed for $path: $e');
      throw const H5Exception('Could not reach the server');
    }
  }

  // ---- Public API (same shapes as the mobile client) ----

  Future<({List<Subject> hero, List<Subject> all})> homeFeed() async {
    final json = await _request(
      'GET',
      '/wefeed-h5api-bff/home?host=themoviebox.xyz',
    );
    return parseH5HomeFeed(json);
  }

  Future<List<Subject>> search(String query, {int page = 1}) async {
    final body = jsonEncode({
      'keyword': query,
      'page': page,
      'perPage': 20,
      'subjectType': 0,
    });
    final json = await _request(
      'POST',
      '/wefeed-h5api-bff/subject/search',
      body: body,
    );
    return parseSearchResults(json);
  }

  Future<Details> detailsByPath(String detailPath) async {
    final json = await _request(
      'GET',
      '/wefeed-h5api-bff/detail?detailPath=${Uri.encodeComponent(detailPath)}',
    );
    return Details.fromH5Json(json);
  }
}
