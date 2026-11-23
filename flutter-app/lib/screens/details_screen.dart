import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../api/models.dart';
import '../api/moviebox_api.dart';
import '../services/downloads.dart';
import '../services/storage.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import 'player_screen.dart';

class DetailsScreen extends StatefulWidget {
  final Subject subject;
  const DetailsScreen({super.key, required this.subject});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  Details? _details;
  String? _error;
  bool _loading = true;
  bool _isFav = false;
  int _season = 1;
  int _episode = 1;
  String? _dubSubjectId;
  Duration? _savedPosition;

  Subject get _subject {
    final d = _details?.subject;
    if (d == null) return widget.subject;
    // A chosen dub is a different subjectId (same title, other language).
    return d;
  }

  String get _activeId => _dubSubjectId ?? widget.subject.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await MovieBoxApi.instance.details(widget.subject.id);
      final fav = await LocalStore.instance.isFavorite(widget.subject.id);
      final pos = await LocalStore.instance.positionFor(
        widget.subject.id,
        d.isSeries ? 1 : 0,
        d.isSeries ? 1 : 0,
      );
      if (!mounted) return;
      setState(() {
        _details = d;
        _loading = false;
        _isFav = fav;
        _savedPosition = pos;
        if (d.seasons.isNotEmpty) {
          _season = d.seasons.first.season;
          _episode = d.seasons.first.episodes.isNotEmpty
              ? d.seasons.first.episodes.first
              : 1;
        }
      });
      await LocalStore.instance.addHistory(widget.subject);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load details. Check your connection and tap Retry.';
      });
    }
  }

  Future<void> _toggleFav() async {
    await LocalStore.instance.toggleFavorite(widget.subject);
    if (mounted) setState(() => _isFav = !_isFav);
  }

  Future<void> _play() async {
    final startAt = await _resumePrompt();
    if (startAt == null && _savedPosition != null) return; // dismissed
    await _openSources(startAt: startAt ?? Duration.zero);
  }

  /// Returns Duration.zero to start over, the saved position to resume,
  /// or null if the dialog was dismissed.
  Future<Duration?> _resumePrompt() async {
    final pos = _savedPosition;
    if (pos == null || pos.inSeconds < 10) return Duration.zero;
    return showDialog<Duration>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Continue watching?'),
        content: Text('Resume from ${_fmt(pos)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, Duration.zero),
            child: const Text('Start over'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, pos),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSources({required Duration startAt}) async {
    List<StreamSource> sources = [];
    bool loading = true;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            if (loading) {
              MovieBoxApi.instance
                  .streams(
                    _activeId,
                    season: _subject.isSeries ? _season : 0,
                    episode: _subject.isSeries ? _episode : 0,
                    detectors: _details?.detectors ?? const [],
                  )
                  .then((s) {
                    if (ctx.mounted) {
                      setSheet(() {
                        sources = s;
                        loading = false;
                        if (s.isEmpty) {
                          error = 'No playable sources found for this title.';
                        }
                      });
                    }
                  })
                  .catchError((e) {
                    if (ctx.mounted) {
                      setSheet(() {
                        loading = false;
                        error = 'Could not load sources. Check your connection and try again.';
                      });
                    }
                  });
            }
            return _sourcesSheet(ctx, sources, loading, error, startAt);
          },
        );
      },
    );
  }

  Widget _sourcesSheet(
    BuildContext ctx,
    List<StreamSource> sources,
    bool loading,
    String? error,
    Duration startAt,
  ) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scroll) => AppCard(
        radius: 24,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _subject.isSeries
                  ? 'Sources · S$_season E$_episode'
                  : 'Sources · ${_subject.title}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Some links are resolver links and may not play in-app — '
              'use “Open externally” if playback fails.',
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
            const SizedBox(height: 12),
            if (loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (error != null)
              Expanded(
                child: Center(child: Text(error, textAlign: TextAlign.center)),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(400),
                  itemCount: sources.length,
                  itemBuilder: (_, i) {
                    final s = sources[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        radius: 14,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                s.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.uploader ?? 'Direct',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  if (s.sizeLabel.isNotEmpty)
                                    Text(
                                      s.sizeLabel,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Download',
                              icon: const Icon(Icons.download_rounded),
                              onPressed: () async {
                                Navigator.pop(ctx);
                                await DownloadManager.instance.start(
                                  subjectId: _activeId,
                                  season: _subject.isSeries ? _season : 0,
                                  episode: _subject.isSeries ? _episode : 0,
                                  title: _subject.title,
                                  url: s.url,
                                  qualityLabel: s.label,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Download started — see Library → Downloads',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Play',
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                color: AppTheme.accent2,
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _playSource(sources, s, startAt);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _playSource(
    List<StreamSource> sources,
    StreamSource source,
    Duration startAt,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          subject: _subject,
          season: _subject.isSeries ? _season : 0,
          episode: _subject.isSeries ? _episode : 0,
          sources: sources,
          initialSource: source,
          startAt: startAt,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _subject;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'poster-${widget.subject.id}',
                    child: s.posterUrl == null
                        ? Container(color: AppTheme.surface)
                        : CachedNetworkImage(
                            imageUrl: s.posterUrl!,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            placeholder: (_, _) =>
                                Container(color: AppTheme.surface),
                            errorWidget: (_, _, _) =>
                                Container(color: AppTheme.surface),
                          ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          AppTheme.bg.withValues(alpha: 0.95),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isFav ? Icons.favorite : Icons.favorite_border,
                  color: _isFav ? AppTheme.accent3 : null,
                ),
                onPressed: _toggleFav,
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_outlined,
                            size: 40,
                            color: AppTheme.muted,
                          ),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _body(s),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(Subject s) {
    final d = _details!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (s.year != null) _metaChip(s.year!),
            if (s.rating != null) _metaChip('★ ${s.rating}'),
            if (s.duration != null) _metaChip(s.duration!),
            if (s.isSeries) _metaChip('TV SERIES'),
          ],
        ),
        if (s.genres.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: s.genres
                .map(
                  (g) => Chip(
                    label: Text(g, style: const TextStyle(fontSize: 12)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _play,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(
              _savedPosition != null && _savedPosition!.inSeconds >= 10
                  ? 'Play · resume ${_fmt(_savedPosition!)}'
                  : 'Play',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        if (d.dubs.length > 1) ...[
          const SizedBox(height: 16),
          const Text(
            'Language / Dub',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Original'),
                selected: _dubSubjectId == null,
                selectedColor: AppTheme.accent,
                onSelected: (_) => setState(() => _dubSubjectId = null),
              ),
              for (final dub in d.dubs)
                ChoiceChip(
                  label: Text(dub.language),
                  selected: _dubSubjectId == dub.subjectId,
                  selectedColor: AppTheme.accent,
                  onSelected: (_) =>
                      setState(() => _dubSubjectId = dub.subjectId),
                ),
            ],
          ),
        ],
        if (d.isSeries && d.seasons.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'Episodes',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: d.seasons
                  .map(
                    (se) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('Season ${se.season}'),
                        selected: _season == se.season,
                        selectedColor: AppTheme.accent,
                        onSelected: (_) => setState(() {
                          _season = se.season;
                          _episode = se.episodes.isNotEmpty
                              ? se.episodes.first
                              : 1;
                        }),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _currentEpisodes(d)
                .map(
                  (ep) => ChoiceChip(
                    label: Text('E$ep'),
                    selected: _episode == ep,
                    selectedColor: AppTheme.accent,
                    onSelected: (_) => setState(() => _episode = ep),
                  ),
                )
                .toList(),
          ),
        ],
        if ((s.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'About',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            s.description!,
            style: const TextStyle(color: AppTheme.muted, height: 1.5),
          ),
        ],
        if (s.director != null || s.stars != null) ...[
          const SizedBox(height: 16),
          if (s.director != null) _fact('Director', s.director!),
          if (s.stars != null) _fact('Cast', s.stars!),
        ],
        const SizedBox(height: 20),
        const Text(
          'Sources are resolved live from the MovieBox API. '
          'This app hosts no media.',
          style: TextStyle(fontSize: 11, color: AppTheme.muted),
        ),
      ],
    );
  }

  List<int> _currentEpisodes(Details d) {
    final se = d.seasons.firstWhere(
      (s) => s.season == _season,
      orElse: () => d.seasons.first,
    );
    return se.episodes;
  }

  Widget _metaChip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(label, style: const TextStyle(fontSize: 12)),
  );

  Widget _fact(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13, color: AppTheme.text),
        children: [
          TextSpan(
            text: '$k: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: v,
            style: const TextStyle(color: AppTheme.muted),
          ),
        ],
      ),
    ),
  );
}

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}
