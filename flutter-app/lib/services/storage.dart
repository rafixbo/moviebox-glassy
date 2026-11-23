import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';

/// Local persistence: favorites, history, continue-watching positions,
/// recent searches. All SharedPreferences — no account, no server.
class LocalStore {
  LocalStore._();
  static final LocalStore instance = LocalStore._();

  static const _favKey = 'favorites';
  static const _histKey = 'history';
  static const _posKey = 'positions';
  static const _recentKey = 'recent_searches';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // ---- Favorites ----
  Future<List<Subject>> favorites() async {
    final p = await _prefs;
    final raw = p.getStringList(_favKey) ?? const [];
    return raw
        .map((s) {
          try {
            return Subject.fromStored(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Subject>()
        .toList();
  }

  Future<bool> isFavorite(String id) async =>
      (await favorites()).any((s) => s.id == id);

  Future<void> toggleFavorite(Subject s) async {
    final p = await _prefs;
    final list = await favorites();
    if (list.any((e) => e.id == s.id)) {
      list.removeWhere((e) => e.id == s.id);
    } else {
      list.insert(0, s);
    }
    await p.setStringList(_favKey, list.map((e) => jsonEncode(e.toJson())).toList());
  }

  // ---- History (most recent first, max 50) ----
  Future<List<Subject>> history() async {
    final p = await _prefs;
    final raw = p.getStringList(_histKey) ?? const [];
    return raw
        .map((s) {
          try {
            return Subject.fromStored(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Subject>()
        .toList();
  }

  Future<void> addHistory(Subject s) async {
    final p = await _prefs;
    final list = await history();
    list.removeWhere((e) => e.id == s.id);
    list.insert(0, s);
    await p.setStringList(
        _histKey, list.take(50).map((e) => jsonEncode(e.toJson())).toList());
  }

  Future<void> clearHistory() async {
    final p = await _prefs;
    await p.remove(_histKey);
  }

  // ---- Continue watching: key "subjectId|s|e" -> {pos, dur, title, poster...} ----
  Future<void> savePosition({
    required Subject subject,
    required int season,
    required int episode,
    required Duration position,
    required Duration duration,
  }) async {
    if (duration.inSeconds <= 0 || position.inSeconds <= 5) return;
    // Don't keep finished items (past 95%).
    final p = await _prefs;
    final key = '${subject.id}|$season|$episode';
    final all = Map<String, dynamic>.from(
        jsonDecode(p.getString(_posKey) ?? '{}') as Map);
    if (position.inSeconds >= duration.inSeconds * 0.95) {
      all.remove(key);
    } else {
      all[key] = {
        'pos': position.inSeconds,
        'dur': duration.inSeconds,
        'title': subject.title,
        'poster': subject.posterUrl,
        'year': subject.year,
        'type': subject.isSeries ? 2 : 1,
        'season': season,
        'episode': episode,
        'at': DateTime.now().millisecondsSinceEpoch,
      };
    }
    await p.setString(_posKey, jsonEncode(all));
  }

  Future<Duration?> positionFor(String subjectId, int season, int episode) async {
    final p = await _prefs;
    final all = jsonDecode(p.getString(_posKey) ?? '{}') as Map;
    final e = all['$subjectId|$season|$episode'];
    if (e is Map && e['pos'] is num) {
      return Duration(seconds: (e['pos'] as num).toInt());
    }
    return null;
  }

  Future<List<ContinueItem>> continueWatching() async {
    final p = await _prefs;
    final all = jsonDecode(p.getString(_posKey) ?? '{}') as Map;
    final items = <ContinueItem>[];
    for (final e in all.entries) {
      final v = e.value;
      if (v is! Map) continue;
      final dur = (v['dur'] is num) ? (v['dur'] as num).toInt() : 0;
      final pos = (v['pos'] is num) ? (v['pos'] as num).toInt() : 0;
      if (dur <= 0 || pos <= 0) continue;
      items.add(ContinueItem(
        subject: Subject(
          id: (e.key as String).split('|').first,
          title: v['title']?.toString() ?? '',
          type: (v['type'] ?? 1) == 2 ? MediaType.series : MediaType.movie,
          year: v['year']?.toString(),
          posterUrl: v['poster']?.toString(),
        ),
        season: (v['season'] is num) ? (v['season'] as num).toInt() : 0,
        episode: (v['episode'] is num) ? (v['episode'] as num).toInt() : 0,
        position: Duration(seconds: pos),
        duration: Duration(seconds: dur),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (v['at'] is num) ? (v['at'] as num).toInt() : 0),
      ));
    }
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  // ---- Recent searches (max 10) ----
  Future<List<String>> recentSearches() async {
    final p = await _prefs;
    return p.getStringList(_recentKey) ?? const [];
  }

  Future<void> addRecentSearch(String q) async {
    final q2 = q.trim();
    if (q2.isEmpty) return;
    final p = await _prefs;
    final list = (p.getStringList(_recentKey) ?? const []).toList();
    list.remove(q2);
    list.insert(0, q2);
    await p.setStringList(_recentKey, list.take(10).toList());
  }
}

class ContinueItem {
  final Subject subject;
  final int season;
  final int episode;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;
  const ContinueItem({
    required this.subject,
    required this.season,
    required this.episode,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  double get progress =>
      duration.inSeconds == 0 ? 0 : position.inSeconds / duration.inSeconds;

  String get label => subject.isSeries ? 'S$season E$episode' : 'Movie';
}
