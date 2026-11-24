// Data models for the MovieBox API (ported from mesamirh/MovieBox-Tui).
///
/// Field names follow the upstream JSON: `subjectId`, `subjectType`,
/// `cover.url`, `resourceLink`, `resourceDetectors`, etc.
library;

enum MediaType { movie, series }

String _id(dynamic v) {
  if (v == null) return '';
  if (v is num) return v.toInt().toString();
  return v.toString();
}

String? _yearOf(dynamic v) {
  if (v == null) return null;
  final m = RegExp(r'(\d{4})').firstMatch(v.toString());
  return m?.group(1);
}

List<String> _genres(dynamic v) {
  if (v is List) {
    return v
        .map((e) => e.toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }
  if (v is String) {
    return v
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return const [];
}

String? _rating(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toStringAsFixed(1);
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

String? _duration(dynamic v) {
  if (v == null) return null;
  if (v is num) {
    final secs = v.toInt();
    if (secs <= 0) return null;
    if (secs < 3600) return '${secs ~/ 60}m';
    return '${secs ~/ 3600}h ${((secs % 3600) ~/ 60)}m';
  }
  final s = v.toString().trim();
  return (s.isEmpty || s == '0' || s == '0m') ? null : s;
}

class Subject {
  final String id;
  final String title;
  final MediaType type;
  final String? year;
  final String? posterUrl;
  final String? description;
  final String? rating;
  final String? duration;
  final List<String> genres;
  final String? director;
  final String? stars;
  final int seasonCount;

  /// Web (H5) detail slug, e.g. `steps-qJ0VewZNhVa`. Present on
  /// subjects coming from the H5 API (home/search); null for subjects
  /// from the mobile API or from local storage written before v1.0.4.
  /// The details screen uses it to load details via the H5 API, which
  /// is the path that works when the mobile hosts are unreachable.
  final String? detailPath;

  const Subject({
    required this.id,
    required this.title,
    required this.type,
    this.year,
    this.posterUrl,
    this.description,
    this.rating,
    this.duration,
    this.genres = const [],
    this.director,
    this.stars,
    this.seasonCount = 0,
    this.detailPath,
  });

  bool get isSeries => type == MediaType.series;

  factory Subject.fromJson(Map<String, dynamic> j) {
    final stype = (j['subjectType'] ?? j['stype'] ?? 1) is num
        ? (j['subjectType'] ?? j['stype'] ?? 1) as num
        : num.tryParse('${j['subjectType'] ?? j['stype']}') ?? 1;
    final cover = j['cover'];
    final poster = cover is Map
        ? cover['url']?.toString()
        : (j['coverUrl'] ?? j['poster'] ?? j['pic'])?.toString();
    return Subject(
      id: _id(j['subjectId'] ?? j['id']),
      title: (j['title'] ?? j['name'] ?? 'Unknown').toString(),
      type: stype.toInt() == 2 ? MediaType.series : MediaType.movie,
      year: _yearOf(j['releaseDate'] ?? j['year'] ?? j['releaseInfo']),
      posterUrl: poster?.isEmpty == true ? null : poster,
      description: (j['description'] ?? j['intro'])?.toString(),
      rating: _rating(j['imdbRatingValue'] ?? j['rating']),
      duration: _duration(j['duration'] ?? j['durationSeconds']),
      genres: _genres(j['genre'] ?? j['genres']),
      director: j['director']?.toString(),
      stars: j['stars']?.toString(),
      seasonCount: (j['season'] is num) ? (j['season'] as num).toInt() : 0,
      detailPath: (j['detailPath'] as String?)?.isEmpty == true
          ? null
          : j['detailPath']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type == MediaType.series ? 2 : 1,
    'year': year,
    'posterUrl': posterUrl,
    'description': description,
    'rating': rating,
    'duration': duration,
    'genres': genres,
    'director': director,
    'stars': stars,
    'detailPath': detailPath,
  };

  factory Subject.fromStored(Map<String, dynamic> j) => Subject(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? 'Unknown',
    type: (j['type'] ?? 1) == 2 ? MediaType.series : MediaType.movie,
    year: j['year'] as String?,
    posterUrl: j['posterUrl'] as String?,
    description: j['description'] as String?,
    rating: j['rating'] as String?,
    duration: j['duration'] as String?,
    genres:
        (j['genres'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    director: j['director'] as String?,
    stars: j['stars'] as String?,
    detailPath: j['detailPath'] as String?,
  );
}

class SeasonInfo {
  final int season;
  final List<int> episodes;
  const SeasonInfo({required this.season, required this.episodes});
}

class Dub {
  final String subjectId;
  final String language;
  final String label;
  const Dub({
    required this.subjectId,
    required this.language,
    required this.label,
  });

  factory Dub.fromJson(Map<String, dynamic> j) => Dub(
    subjectId: _id(j['subjectId'] ?? j['id']),
    language: (j['lanName'] ?? j['language'] ?? j['lang'] ?? 'Unknown')
        .toString(),
    label:
        (j['title'] ?? j['name'] ?? j['lanName'] ?? j['language'] ?? 'Unknown')
            .toString(),
  );
}

class Details {
  final Subject subject;
  final List<SeasonInfo> seasons;
  final List<Dub> dubs;
  final List<Map<String, dynamic>> detectors;

  const Details({
    required this.subject,
    this.seasons = const [],
    this.dubs = const [],
    this.detectors = const [],
  });

  bool get isSeries => subject.isSeries || seasons.isNotEmpty;

  /// Parse the H5 (web) `/wefeed-h5api-bff/detail` payload. Its shape
  /// differs from the mobile one: `data.subject` is the subject map and
  /// seasons live in `data.resource.seasons` ([{se, maxEp,
  /// resolutions[]}]); dubs live in `data.subject.dubs`. The merged
  /// subject map is fed to [Details.fromJson], which already knows how
  /// to build seasons from `maxEp` and dubs from `dubs`.
  factory Details.fromH5Json(Map<String, dynamic> root) {
    final data = root['data'];
    final subj = (data is Map && data['subject'] is Map)
        ? Map<String, dynamic>.from(data['subject'] as Map)
        : <String, dynamic>{};
    final resource = (data is Map && data['resource'] is Map)
        ? data['resource'] as Map
        : null;
    final seasons = resource?['seasons'];
    if (seasons is List) {
      // Movies come back with a single [{se: 0, maxEp: 0}] entry; drop
      // it (and any season with no episodes) so a movie is not
      // mistaken for a series (Details.isSeries checks seasons).
      subj['seasons'] = seasons
          .where(
            (s) =>
                s is Map &&
                (s['maxEp'] is num) &&
                (s['maxEp'] as num).toInt() > 0,
          )
          .toList();
    }
    return Details.fromJson({
      'data': {'subject': subj},
    });
  }

  /// Parse the `/subject-api/get` payload. `seasonJson` is the optional
  /// `/subject-api/season-info` payload (series only).
  factory Details.fromJson(
    Map<String, dynamic> root, [
    Map<String, dynamic>? seasonJson,
  ]) {
    final data = root['data'];
    final subjJson = (data is Map && data['subject'] is Map)
        ? Map<String, dynamic>.from(data['subject'] as Map)
        : (root['subject'] is Map
              ? Map<String, dynamic>.from(root['subject'] as Map)
              : Map<String, dynamic>.from(data is Map ? data : root));
    // Merge seasons from the season-info call into the subject json.
    if (seasonJson != null) {
      final sd = seasonJson['data'] ?? seasonJson;
      if (sd is Map && sd['seasons'] is List) {
        subjJson['seasons'] = sd['seasons'];
      } else if (seasonJson['seasons'] is List) {
        subjJson['seasons'] = seasonJson['seasons'];
      }
    }
    final seasons = <SeasonInfo>[];
    final sList = subjJson['seasons'];
    if (sList is List) {
      for (final s in sList) {
        if (s is! Map) continue;
        final se = (s['se'] is num) ? (s['se'] as num).toInt() : 1;
        final eps = <int>[];
        final epNums = s['episodeNumbers'];
        if (epNums is List) {
          for (final e in epNums) {
            if (e is num) eps.add(e.toInt());
          }
        } else if (s['maxEp'] is num) {
          for (var i = 1; i <= (s['maxEp'] as num).toInt(); i++) {
            eps.add(i);
          }
        }
        seasons.add(SeasonInfo(season: se, episodes: eps));
      }
    }
    final dubs = <Dub>[];
    final dList = subjJson['dubs'];
    if (dList is List) {
      for (final d in dList) {
        if (d is Map) dubs.add(Dub.fromJson(Map<String, dynamic>.from(d)));
      }
    }
    final detectors = <Map<String, dynamic>>[];
    final det = subjJson['resourceDetectors'];
    if (det is List) {
      for (final d in det) {
        if (d is Map) detectors.add(Map<String, dynamic>.from(d));
      }
    }
    return Details(
      subject: Subject.fromJson(subjJson),
      seasons: seasons,
      dubs: dubs,
      detectors: detectors,
    );
  }
}

/// One playable source for a title / episode.
class StreamSource {
  final String url;
  final String label; // e.g. "720p", "1080p", "Direct"
  final int resolution; // 0 when unknown
  final int? sizeBytes;
  final String? uploader;
  final String? resourceId;

  /// Session cookie the CDN requires for this stream (the `signCookie`
  /// from play-info, e.g. `Edge-Cache-Cookie=...`). The DASH manifest
  /// AND every .m4s segment return 403 without it — it is the key that
  /// unlocks in-app playback. Null for plain direct files (resource
  /// mp4s carry their own `?sign=` query instead).
  final String? cookie;

  const StreamSource({
    required this.url,
    required this.label,
    this.resolution = 0,
    this.sizeBytes,
    this.uploader,
    this.resourceId,
    this.cookie,
  });

  String get sizeLabel {
    final b = sizeBytes;
    if (b == null || b <= 0) return '';
    if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(1)} GB';
    if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(0)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }
}

/// One external subtitle track (from get-ext-captions).
class CaptionTrack {
  final String name;
  final String url;
  const CaptionTrack({required this.name, required this.url});
}

/// Parse get-ext-captions payload: data.extCaptions[] {lanName/lan, url}.
/// Skips empty/tiny entries (mirrors the Rust filter).
List<CaptionTrack> parseCaptions(Map<String, dynamic> root) {
  final data = root['data'];
  final caps =
      (data is Map ? data['extCaptions'] : null) as List? ??
      (root['extCaptions'] as List?) ??
      const [];
  final seen = <String>{};
  final out = <CaptionTrack>[];
  for (final c in caps) {
    if (c is! Map) continue;
    final url = c['url']?.toString() ?? '';
    if (url.isEmpty || url.contains('aa348f2541d13ffe')) continue;
    final size = c['size'] is num
        ? (c['size'] as num).toInt()
        : int.tryParse('${c['size']}') ?? 0;
    if (size > 0 && size <= 50) continue;
    final name = (c['lanName'] ?? c['lan'] ?? 'Unknown').toString();
    if (name.toLowerCase() == 'in' && size <= 100) continue;
    if (!seen.add(url)) continue;
    out.add(CaptionTrack(name: name, url: url));
  }
  return out;
}

/// Parse the search payload: data.results[0].subjects[], fallback data.list[],
/// fallback data.items[] (H5 web search returns `data.items`).
List<Subject> parseSearchResults(Map<String, dynamic> root) {
  final data = root['data'];
  List? subjects;
  if (data is Map) {
    final results = data['results'];
    if (results is List && results.isNotEmpty && results.first is Map) {
      subjects = (results.first as Map)['subjects'] as List?;
    }
    subjects ??= data['list'] as List?;
    subjects ??= data['items'] as List?;
  }
  subjects ??= root['list'] as List?;
  subjects ??= root['items'] as List?;
  if (subjects == null) return const [];
  return subjects
      .whereType<Map>()
      .map((m) => Subject.fromJson(Map<String, dynamic>.from(m)))
      .where((s) => s.id.isNotEmpty)
      .toList();
}

/// Parse the H5 (web) homepage payload: `data.operatingList[]` sections.
/// BANNER sections carry `banner.items[].subject`; content sections carry
/// `subjects[]` directly. Returns the same (hero, all) shape as
/// [parseHomeFeed] so the home screen needs no changes. Non-content
/// sections (e.g. SPORT_LIVE with no subjects) are skipped.
({List<Subject> hero, List<Subject> all}) parseH5HomeFeed(
  Map<String, dynamic> root,
) {
  final data = root['data'];
  final sections =
      (data is Map ? data['operatingList'] : null) as List? ??
      (root['operatingList'] as List?) ??
      const [];
  final hero = <Subject>[];
  final all = <Subject>[];
  final seen = <String>{};
  for (final g in sections) {
    if (g is! Map) continue;
    final isBanner = g['type']?.toString() == 'BANNER';
    final groupSubjects = <Map<String, dynamic>>[];
    final banner = g['banner'];
    if (banner is Map && banner['items'] is List) {
      for (final b in banner['items'] as List) {
        if (b is Map && b['subject'] is Map) {
          groupSubjects.add(Map<String, dynamic>.from(b['subject'] as Map));
        }
      }
    }
    final custom = g['customData'];
    if (custom is Map && custom['items'] is List) {
      for (final c in custom['items'] as List) {
        if (c is Map && c['subject'] is Map) {
          groupSubjects.add(Map<String, dynamic>.from(c['subject'] as Map));
        }
      }
    }
    final subs = g['subjects'];
    if (subs is List) {
      for (final s in subs) {
        if (s is Map) groupSubjects.add(Map<String, dynamic>.from(s));
      }
    }
    for (final s in groupSubjects) {
      final sub = Subject.fromJson(s);
      if (sub.id.isEmpty) continue;
      if (isBanner &&
          hero.length < 8 &&
          !hero.any((h) => h.id == sub.id)) {
        hero.add(sub);
      }
      if (seen.add(sub.id)) all.add(sub);
    }
  }
  return (hero: hero, all: all);
}

/// Parse the homepage payload: data.items[] groups -> banner / customData /
/// subjects. Returns (hero subjects, all unique subjects in order).
({List<Subject> hero, List<Subject> all}) parseHomeFeed(
  Map<String, dynamic> root,
) {
  final data = root['data'];
  final items =
      (data is Map ? data['items'] : null) as List? ??
      (root['items'] as List?) ??
      const [];
  final hero = <Subject>[];
  final all = <Subject>[];
  final seen = <String>{};
  for (final g in items) {
    if (g is! Map) continue;
    final groupSubjects = <Map<String, dynamic>>[];
    final banner = g['banner'];
    if (banner is Map && banner['banners'] is List) {
      for (final b in banner['banners'] as List) {
        if (b is Map && b['subject'] is Map) {
          groupSubjects.add(Map<String, dynamic>.from(b['subject'] as Map));
        }
      }
    }
    final custom = g['customData'];
    if (custom is Map && custom['items'] is List) {
      for (final c in custom['items'] as List) {
        if (c is Map && c['subject'] is Map) {
          groupSubjects.add(Map<String, dynamic>.from(c['subject'] as Map));
        }
      }
    }
    final subs = g['subjects'];
    if (subs is List) {
      for (final s in subs) {
        if (s is Map) groupSubjects.add(Map<String, dynamic>.from(s));
      }
    }
    final isBannerGroup =
        (g['type']?.toString() == 'BANNER') ||
        (banner is Map && banner['banners'] is List);
    for (final s in groupSubjects) {
      final sub = Subject.fromJson(s);
      if (sub.id.isEmpty) continue;
      if (isBannerGroup &&
          hero.length < 8 &&
          !hero.any((h) => h.id == sub.id)) {
        hero.add(sub);
      }
      if (seen.add(sub.id)) all.add(sub);
    }
  }
  return (hero: hero, all: all);
}

/// Parse stream sources from play-info + resource list + detectors.
/// Mirrors the Rust `episode_streams` logic (minus the TUI bits).
/// Clean a raw `signCookie` value into a single `Cookie` header value:
/// trim, drop empty parts, join with "; " (mirrors the upstream
/// MovieBox-Tui adapter). Returns null when there is no cookie.
String? cleanSignCookie(dynamic raw) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  final parts = s
      .trim()
      .replaceAll(RegExp(r';+$'), '')
      .split(';')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  return parts.join('; ');
}

List<StreamSource> parseStreamSources({
  required Map<String, dynamic>? playInfo,
  required Map<String, dynamic>? resource,
  required List<Map<String, dynamic>> detectors,
  required int season,
  required int episode,
}) {
  const placeholder =
      'https://macdn.aoneroom.com/other/2026/10/10/80da52722ee7de7a4303290af6783424.mp4';
  final out = <StreamSource>[];
  final seen = <String>{};

  void add(String? url, int res, int? size, String? up, String? rid,
      [String? cookie]) {
    if (url == null || url.isEmpty || url == placeholder) return;
    final base = url.split('?').first;
    if (!seen.add(base)) return;
    out.add(
      StreamSource(
        url: url,
        label: res > 0 ? '${res}p' : 'Direct',
        resolution: res,
        sizeBytes: size,
        uploader: up,
        resourceId: rid,
        cookie: cookie,
      ),
    );
  }

  int resOf(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  int? sizeOf(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  // 1) play-info streams (direct HLS/mp4 when present).
  final piData = playInfo?['data'];
  final streams = (piData is Map ? piData['streams'] : null) as List?;
  if (streams != null) {
    for (final s in streams) {
      if (s is Map) {
        add(
          s['url']?.toString(),
          resOf(s['resolution']),
          sizeOf(s['size']),
          null,
          null,
          // The CDN session cookie — without it the DASH manifest and
          // every segment return 403. This was the playback failure.
          cleanSignCookie(s['signCookie']),
        );
      }
    }
  }
  // 2) resource list.
  final rData = resource?['data'];
  final list = (rData is Map ? rData['list'] : null) as List?;
  if (list != null) {
    for (final item in list) {
      if (item is! Map) continue;
      if (season != 0 || episode != 0) {
        final se = resOf(item['se']);
        final ep = resOf(item['ep']);
        if ((se != 0 || ep != 0) && (se != season || ep != episode)) continue;
      }
      add(
        (item['resourceLink'] ?? item['url'])?.toString(),
        resOf(item['resolution']),
        sizeOf(item['size']),
        item['uploadBy']?.toString(),
        _id(item['resourceId'] ?? item['id']),
        cleanSignCookie(item['signCookie']),
      );
    }
  }
  // 3) detectors (details payload): downloadUrl + resolutionList.
  for (final d in detectors) {
    final resList = d['resolutionList'] as List?;
    if (resList != null && resList.isNotEmpty) {
      for (final r in resList) {
        if (r is Map) {
          add(
            (r['resourceLink'] ?? r['downloadUrl'])?.toString(),
            resOf(r['resolution']),
            sizeOf(r['firstSize'] ?? r['size']),
            d['uploadBy']?.toString(),
            _id(d['resourceId']),
            cleanSignCookie(r['signCookie'] ?? d['signCookie']),
          );
        }
      }
      continue;
    }
    add(
      d['downloadUrl']?.toString(),
      0,
      sizeOf(d['firstSize']),
      d['uploadBy']?.toString(),
      _id(d['resourceId']),
      cleanSignCookie(d['signCookie']),
    );
  }

  out.sort((a, b) {
    final c = b.resolution.compareTo(a.resolution);
    if (c != 0) return c;
    return (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0);
  });
  return out;
}
