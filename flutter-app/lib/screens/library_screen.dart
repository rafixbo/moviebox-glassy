import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../api/models.dart';
import '../services/downloads.dart';
import '../services/storage.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import 'details_screen.dart';
import 'player_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Subject> _favs = [];
  List<ContinueItem> _cw = [];
  List<Subject> _history = [];
  List<DownloadItem> _downloads = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _refresh();
    DownloadManager.instance.rescan();
    DownloadManager.instance.stream.listen((items) {
      if (mounted) setState(() => _downloads = items);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final favs = await LocalStore.instance.favorites();
    final cw = await LocalStore.instance.continueWatching();
    final hist = await LocalStore.instance.history();
    if (!mounted) return;
    setState(() {
      _favs = favs;
      _cw = cw;
      _history = hist;
      _downloads = DownloadManager.instance.items;
    });
  }

  void _open(Subject s) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => DetailsScreen(subject: s)))
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: AppTheme.accent,
          labelColor: AppTheme.text,
          unselectedLabelColor: AppTheme.muted,
          tabs: const [
            Tab(text: 'Favorites'),
            Tab(text: 'Watching'),
            Tab(text: 'Downloads'),
            Tab(text: 'History'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _favTab(),
              _watchingTab(),
              _downloadsTab(),
              _historyTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _empty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTheme.muted),
      ),
    ),
  );

  Widget _favTab() => _favs.isEmpty
      ? _empty('No favorites yet.\nTap the heart on any title to save it here.')
      : PosterGrid(items: _favs, onTap: _open);

  Widget _watchingTab() {
    if (_cw.isEmpty) {
      return _empty(
        'Nothing in progress.\nStart a title and your position is saved here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
      itemCount: _cw.length,
      itemBuilder: (_, i) {
        final c = _cw[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            padding: const EdgeInsets.all(10),
            onTap: () => _open(c.subject),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 56,
                    height: 84,
                    child: c.subject.posterUrl == null
                        ? Container(
                            color: AppTheme.surface,
                            child: const Icon(
                              Icons.movie_outlined,
                              color: AppTheme.muted,
                            ),
                          )
                        : Image.network(
                            c.subject.posterUrl!,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.subject.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${c.label} · ${_fmt(c.position)} / ${_fmt(c.duration)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: c.progress,
                        minHeight: 4,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation(
                          AppTheme.accent2,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.play_arrow_rounded),
                  onPressed: () => _open(c.subject),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _downloadsTab() {
    if (_downloads.isEmpty) {
      return _empty(
        'No downloads yet.\nPick a quality in a title and tap the download icon.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
      itemCount: _downloads.length,
      itemBuilder: (_, i) {
        final d = _downloads[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => DownloadManager.instance.delete(d.id),
                    ),
                  ],
                ),
                Text(
                  d.label,
                  style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
                const SizedBox(height: 8),
                if (d.status == DownloadStatus.downloading ||
                    d.status == DownloadStatus.paused)
                  LinearProgressIndicator(
                    value: d.progress > 0 ? d.progress : null,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                    borderRadius: BorderRadius.circular(2),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(switch (d.status) {
                      DownloadStatus.downloading =>
                        '${(d.progress * 100).round()}% downloading',
                      DownloadStatus.paused => 'Paused',
                      DownloadStatus.completed => 'Ready offline',
                      DownloadStatus.failed => 'Failed — tap to retry',
                    }, style: const TextStyle(fontSize: 12)),
                    const Spacer(),
                    if (d.status == DownloadStatus.paused)
                      TextButton(
                        onPressed: () => DownloadManager.instance.resume(d.id),
                        child: const Text('Resume'),
                      ),
                    if (d.status == DownloadStatus.completed)
                      FilledButton.icon(
                        onPressed: () => _playOffline(d),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Play offline'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _playOffline(DownloadItem d) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          subject: Subject(id: d.id, title: d.title, type: MediaType.movie),
          season: 0,
          episode: 0,
          sources: const [],
          initialSource: StreamSource(url: d.filePath, label: 'Offline'),
          offlineFilePath: d.filePath,
        ),
      ),
    );
  }

  Widget _historyTab() {
    if (_history.isEmpty) {
      return _empty('No history yet.\nTitles you open will show up here.');
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              await LocalStore.instance.clearHistory();
              _refresh();
            },
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('Clear history'),
          ),
        ),
        Expanded(
          child: PosterGrid(items: _history, onTap: _open),
        ),
      ],
    );
  }
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
