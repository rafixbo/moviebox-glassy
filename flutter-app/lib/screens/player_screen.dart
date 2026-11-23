import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/models.dart';
import '../api/moviebox_api.dart';
import '../services/storage.dart';
import '../services/stream_relay.dart';
import '../theme.dart';

/// Material in-app player (media_kit — Android + Windows).
///
/// Streams carry the CDN session cookie from the API (`signCookie`):
/// without it the DASH manifest and segments return 403. DASH/HLS
/// sources play through a local loopback relay ([StreamRelay]): the
/// player opens `http://127.0.0.1:<port>/manifest.mpd` and the relay
/// attaches UA + Referer + Cookie to every upstream request, so the
/// cookie reaches every segment (media_kit only sets `httpHeaders`
/// once at load time, and playback stalled after exactly one 5 s
/// segment — the classic later-segments-without-cookie failure).
/// Direct files keep the header-on-URL path. On failure the player
/// auto-recovers — one fresh source refresh, then the next source —
/// before ever showing the error card. Some resource links are still
/// *resolver* links (e.g. ugc-video.com) rather than direct media
/// files; those may fail in-app even with the cookie, and the error
/// screen offers "Open externally" for them.
class PlayerScreen extends StatefulWidget {
  final Subject subject;
  final int season;
  final int episode;
  final List<StreamSource> sources;
  final StreamSource initialSource;
  final Duration startAt;
  final String? offlineFilePath;

  /// Detector payloads for the details screen, so a recovery refresh
  /// can re-fetch the same source list (with fresh session cookies).
  final List<Map<String, dynamic>> detectors;

  const PlayerScreen({
    super.key,
    required this.subject,
    required this.season,
    required this.episode,
    required this.sources,
    required this.initialSource,
    this.startAt = Duration.zero,
    this.offlineFilePath,
    this.detectors = const [],
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  late StreamSource _current;
  List<CaptionTrack> _subs = [];
  String? _subLabel;
  bool _controlsVisible = true;
  bool _hasError = false;
  bool _loading = true;
  Timer? _hideTimer;
  Timer? _sleepTimer;
  Duration? _sleepLeft;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  double _rate = 1.0;
  String? _gestureHint;
  Timer? _gestureTimer;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _errorSub;
  double _lastBrightness = 0.5;
  int _saveTick = 0;

  bool get _isOffline => widget.offlineFilePath != null;

  // ---- Auto-recovery state ----
  // On a playback error the player does NOT show the error card right
  // away. It first re-fetches fresh sources once (a new session cookie
  // — cookies are time-limited), then falls back to the next untried
  // source, up to [_maxAutoTries] attempts in total. Only when every
  // attempt is exhausted does the friendly error card appear.
  static const int _maxAutoTries = 3;
  late List<StreamSource> _sources;
  final Set<String> _tried = {};
  bool _recovering = false;
  bool _refreshed = false;
  int _autoTries = 0;

  /// Local loopback relay for DASH/HLS sources. The player opens the
  /// relay's loopback manifest instead of the raw CDN URL, so the
  /// session cookie reaches every segment (see stream_relay.dart).
  /// Null for direct files and offline playback.
  StreamRelay? _relay;

  bool _isRelaySource(StreamSource s) {
    if (_isOffline) return false;
    final base = s.url.split('?').first.toLowerCase();
    return base.endsWith('.mpd') || base.endsWith('.m3u8');
  }

  /// Fresh source for the relay when a segment 403s mid-playback:
  /// same manifest when possible (segment URLs are stable across
  /// mints — only the cookie changes), else any DASH/HLS source.
  Future<StreamSource?> _refreshRelaySource() async {
    try {
      final fresh = await MovieBoxApi.instance.streams(
        widget.subject.id,
        season: widget.season,
        episode: widget.episode,
        detectors: widget.detectors,
      );
      final base = _urlKey(_current);
      for (final s in fresh) {
        if (_urlKey(s) == base) return s;
      }
      for (final s in fresh) {
        if (_isRelaySource(s)) return s;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _urlKey(StreamSource s) => s.url.split('?').first;

  @override
  void initState() {
    super.initState();
    _current = widget.initialSource;
    _sources = List.of(widget.sources);
    _player = Player();
    _videoController = VideoController(_player);
    _posSub = _player.stream.position.listen((p) {
      _position = p;
      if (++_saveTick % 20 == 0) _savePosition(); // ~every 10s at 2Hz
      if (mounted) setState(() {});
    });
    _durSub = _player.stream.duration.listen((d) {
      _duration = d;
      if (mounted) setState(() {});
    });
    _playingSub = _player.stream.playing.listen((v) {
      _playing = v;
      if (mounted) setState(() {});
    });
    _completedSub = _player.stream.completed.listen((done) {
      if (done) _savePosition();
    });
    _errorSub = _player.stream.error.listen((e) {
      if (e.isNotEmpty && mounted) {
        // The raw player error often contains the direct stream URL.
        // It goes to the log only — the UI never shows URLs, anywhere.
        debugPrint('[Player] playback error: $e');
        _tryRecover();
      }
    });
    _open(_current, startAt: widget.startAt);
    _loadSubtitles();
    _armHideTimer();
    _initBrightness();
  }

  Future<void> _initBrightness() async {
    try {
      _lastBrightness = await ScreenBrightness().application;
    } catch (_) {}
  }

  Future<void> _loadSubtitles() async {
    if (_isOffline || _current.resourceId == null) return;
    final subs = await MovieBoxApi.instance.captions(
      widget.subject.id,
      _current.resourceId!,
    );
    if (mounted) setState(() => _subs = subs);
  }

  Future<void> _open(StreamSource source, {required Duration startAt}) async {
    // Guard: recovery can outlive the screen (user pressed Back while
    // the player was opening). setState/seek after dispose used to
    // throw uncaught async errors — one of the Windows crash paths.
    if (!mounted) return;
    setState(() {
      _loading = true;
      _hasError = false;
      _current = source;
    });
    _tried.add(_urlKey(source));
    // DASH/HLS go through the local relay: the player opens the
    // loopback manifest and the relay attaches UA + Referer + Cookie
    // to every upstream request (manifest + every segment). Direct
    // files open with UA only — the bcdn CDN 429s any mp4 request
    // carrying the sportslive.wine Referer, so it must never be sent
    // on a direct file (verified live 2026-11-23).
    var mediaUrl = source.url;
    Map<String, String>? headers = directFileHeaders();
    if (_isRelaySource(source)) {
      try {
        _relay ??= StreamRelay(refreshSource: _refreshRelaySource);
        await _relay!.start(source);
        mediaUrl = _relay!.manifestUrl;
        headers = null; // loopback needs no auth headers
      } catch (e) {
        // Relay unavailable (bind failure etc.) — fall back to the
        // direct path with headers rather than failing playback.
        debugPrint('[Player] relay start failed, direct open: $e');
        await _relay?.stop();
        _relay = null;
      }
    } else {
      await _relay?.stop();
      _relay = null;
    }
    final media = _isOffline
        ? Media(widget.offlineFilePath!)
        : Media(mediaUrl, httpHeaders: headers);
    try {
      await _player.open(media, play: true);
    } catch (e) {
      debugPrint('[Player] open failed: $e');
      _tryRecover();
      return;
    }
    if (startAt > Duration.zero && mounted) {
      // Give the player a moment to buffer before seeking. The seek
      // sits outside the open try/catch on purpose — a disposed player
      // or a failed seek must not throw an uncaught async error.
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      try {
        await _player.seek(startAt);
      } catch (e) {
        debugPrint('[Player] resume seek failed: $e');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Automatic recovery after a playback error. Bounded: at most
  /// [_maxAutoTries] automatic attempts, then the error card appears.
  /// First attempt is a fresh source refresh (new session cookie —
  /// cookies are time-limited, so a stale one is the most common
  /// failure), then the next untried source in the list — never the
  /// URL that just failed, so the budget always reaches new sources.
  Future<void> _tryRecover() async {
    if (_recovering || _hasError || !mounted) return;
    if (_autoTries >= _maxAutoTries) {
      _showErrorCard();
      return;
    }
    _recovering = true;
    _autoTries++;
    debugPrint(
      '[Player] auto-recovery attempt $_autoTries/$_maxAutoTries',
    );

    // 1) Fresh sources once (fresh cookie) — the most common fix.
    if (!_refreshed && !_isOffline) {
      _refreshed = true;
      try {
        final fresh = await MovieBoxApi.instance.streams(
          widget.subject.id,
          season: widget.season,
          episode: widget.episode,
          detectors: widget.detectors,
        );
        if (fresh.isNotEmpty && mounted) {
          _sources = fresh;
          // Fresh cookies for the remaining sources — but do NOT
          // retry the URL that just failed: it already failed with
          // this player, and re-opening it wastes one of the three
          // attempts (a 4-mp4 + DASH title would then never reach
          // the playable DASH source). The relay already refreshes
          // the DASH cookie itself on 403, and direct mp4s carry no
          // cookie, so a same-URL retry buys nothing anymore.
          final failed = _urlKey(_current);
          _tried.clear();
          _tried.add(failed);
          final next = _nextUntried();
          if (next != null) {
            _recovering = false;
            await _open(next, startAt: _position);
            return;
          }
        }
      } catch (e) {
        debugPrint('[Player] source refresh failed: $e');
      }
    }

    // 2) Next untried source (e.g. a direct mp4, which needs no cookie).
    final next = _nextUntried();
    _recovering = false;
    if (next != null) {
      await _open(next, startAt: _position);
      return;
    }

    // 3) Nothing left to try.
    _showErrorCard();
  }

  StreamSource? _nextUntried() {
    for (final s in _sources) {
      if (!_tried.contains(_urlKey(s))) return s;
    }
    return null;
  }

  void _showErrorCard() {
    if (!mounted) return;
    setState(() {
      _hasError = true;
      _loading = false;
    });
  }

  /// Retry from the error card: fresh recovery budget (one more
  /// refresh + fallback round) instead of replaying the dead source.
  Future<void> _manualRetry() async {
    setState(() {
      _hasError = false;
      _loading = true;
    });
    _refreshed = false;
    _autoTries = 0;
    _recovering = false;
    await _tryRecover();
  }

  Future<void> _savePosition() async {
    if (_isOffline || _duration.inSeconds <= 0) return;
    await LocalStore.instance.savePosition(
      subject: widget.subject,
      season: widget.season,
      episode: widget.episode,
      position: _position,
      duration: _duration,
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _sleepTimer?.cancel();
    _gestureTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _errorSub?.cancel();
    unawaited(_relay?.stop());
    _savePosition();
    _player.dispose();
    super.dispose();
  }

  void _armHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _armHideTimer();
  }

  void _seekBy(Duration delta) {
    final target = _position + delta;
    _player.seek(
      target < Duration.zero
          ? Duration.zero
          : (target > _duration ? _duration : target),
    );
    _showGestureHint(delta.isNegative ? '−10s' : '+10s');
  }

  void _showGestureHint(String text) {
    setState(() => _gestureHint = text);
    _gestureTimer?.cancel();
    _gestureTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _gestureHint = null);
    });
  }

  Future<void> _onVerticalDrag(double dy, bool leftSide) async {
    if (leftSide) {
      // Brightness.
      try {
        final next = (_lastBrightness - dy / 300).clamp(0.05, 1.0);
        await ScreenBrightness().setApplicationScreenBrightness(next);
        _lastBrightness = next;
        _showGestureHint('Brightness ${(next * 100).round()}%');
      } catch (_) {
        _showGestureHint('Brightness not available');
      }
    } else {
      // Volume.
      final vol = (_player.state.volume + (-dy / 2)).clamp(0.0, 100.0);
      await _player.setVolume(vol);
      _showGestureHint('Volume ${vol.round()}%');
    }
  }

  void _setSleep(Duration? d) {
    _sleepTimer?.cancel();
    setState(() => _sleepLeft = d);
    if (d == null) return;
    _sleepTimer = Timer(d, () {
      _player.pause();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sleep timer stopped playback')),
        );
      }
    });
  }

  Future<void> _switchQuality(StreamSource s) async {
    final pos = _position;
    // Explicit user choice: fresh recovery budget for the new source.
    _tried.clear();
    _autoTries = 0;
    _refreshed = false;
    await _open(s, startAt: pos);
    await _loadSubtitles();
  }

  Future<void> _pickSubtitle(CaptionTrack? sub) async {
    if (sub == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      setState(() => _subLabel = null);
    } else {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(sub.url, title: sub.name),
      );
      setState(() => _subLabel = sub.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: _toggleControls,
              onDoubleTapDown: (d) {
                final w = MediaQuery.sizeOf(context).width;
                _seekBy(
                  d.globalPosition.dx < w / 2
                      ? const Duration(seconds: -10)
                      : const Duration(seconds: 10),
                );
              },
              onVerticalDragUpdate: (d) {
                final w = MediaQuery.sizeOf(context).width;
                _onVerticalDrag(d.delta.dy, d.globalPosition.dx < w / 2);
              },
              child: Video(
                controller: _videoController,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              ),
            ),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_gestureHint != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _gestureHint!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (_hasError) _errorCard(),
            if (_controlsVisible && !_hasError) _controls(),
          ],
        ),
      ),
    );
  }

  Widget _errorCard() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text(
              'Playback failed',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'This source could not be played in-app. '
              'Try another quality or an external player.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _manualRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(_current.url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open externally'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _controls() => Column(
    children: [
      // Top bar.
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Text(
                widget.subject.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (_sources.length > 1)
              _menuButton(
                icon: Icons.hd_outlined,
                label: 'Quality',
                items: _sources
                    .map(
                      (s) => PopupMenuItem<StreamSource>(
                        value: s,
                        child: Text(
                          '${s.label}${s.sizeLabel.isNotEmpty ? ' · ${s.sizeLabel}' : ''}',
                        ),
                      ),
                    )
                    .toList(),
                onSelected: _switchQuality,
              ),
            _menuButton(
              icon: Icons.speed,
              label: 'Speed',
              items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                  .map(
                    (r) =>
                        PopupMenuItem<double>(value: r, child: Text('${r}x')),
                  )
                  .toList(),
              onSelected: (r) async {
                await _player.setRate(r);
                setState(() => _rate = r);
              },
            ),
            _menuButton(
              icon: Icons.subtitles_outlined,
              label: 'Subtitles',
              items: [
                const PopupMenuItem<CaptionTrack?>(
                  value: null,
                  child: Text('Off'),
                ),
                ..._subs.map(
                  (s) => PopupMenuItem<CaptionTrack?>(
                    value: s,
                    child: Text(s.name),
                  ),
                ),
              ],
              onSelected: _pickSubtitle,
            ),
            _menuButton(
              icon: Icons.bedtime_outlined,
              label: 'Sleep timer',
              items: const [
                PopupMenuItem<Duration?>(value: null, child: Text('Off')),
                PopupMenuItem<Duration?>(
                  value: Duration(minutes: 15),
                  child: Text('15 min'),
                ),
                PopupMenuItem<Duration?>(
                  value: Duration(minutes: 30),
                  child: Text('30 min'),
                ),
                PopupMenuItem<Duration?>(
                  value: Duration(minutes: 60),
                  child: Text('60 min'),
                ),
              ],
              onSelected: _setSleep,
            ),
          ],
        ),
      ),
      const Spacer(),
      // Bottom bar.
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text(_fmt(_position), style: const TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _position.inMilliseconds.toDouble().clamp(
                      0,
                      _duration.inMilliseconds.toDouble(),
                    ),
                    max: _duration.inMilliseconds.toDouble() > 0
                        ? _duration.inMilliseconds.toDouble()
                        : 1,
                    onChanged: (v) =>
                        _player.seek(Duration(milliseconds: v.round())),
                    activeColor: AppTheme.accent,
                  ),
                ),
                Text(_fmt(_duration), style: const TextStyle(fontSize: 12)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Back 10s',
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => _seekBy(const Duration(seconds: -10)),
                ),
                const SizedBox(width: 12),
                IconButton(
                  iconSize: 56,
                  icon: Icon(
                    _playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                  onPressed: () {
                    _playing ? _player.pause() : _player.play();
                    _armHideTimer();
                  },
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Forward 10s',
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => _seekBy(const Duration(seconds: 10)),
                ),
              ],
            ),
            if (_sleepLeft != null || _subLabel != null || _rate != 1.0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    if (_rate != 1.0) '${_rate}x',
                    if (_subLabel != null) 'CC: $_subLabel',
                    if (_sleepLeft != null)
                      'Sleep ${_sleepLeft!.inMinutes} min',
                  ].join('  ·  '),
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _menuButton<T>({
    required IconData icon,
    required String label,
    required List<PopupMenuItem<T>> items,
    required void Function(T) onSelected,
  }) => PopupMenuButton<T>(
    icon: Icon(icon),
    tooltip: label,
    color: AppTheme.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    onSelected: onSelected,
    itemBuilder: (_) => items,
  );
}

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
