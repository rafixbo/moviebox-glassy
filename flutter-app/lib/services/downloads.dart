import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../api/moviebox_api.dart';

/// Offline downloads. Files land in the platform Downloads folder
/// (Android: app documents / Downloads; Windows: user Downloads).
/// Same UA + Referer headers as playback, plus the session Cookie
/// when the source carries one (DASH downloads 403 without it).
/// Pause/resume uses HTTP Range when the server supports it;
/// otherwise the download restarts.
class DownloadItem {
  final String id; // subjectId|season|episode
  final String title;
  final String label; // e.g. "S1 E2 · 720p"
  final String filePath;
  final String url; // source URL (needed for pause/resume)
  final String? cookie; // CDN session cookie, when the source has one
  final int totalBytes;
  final int downloadedBytes;
  final DownloadStatus status;

  const DownloadItem({
    required this.id,
    required this.title,
    required this.label,
    required this.filePath,
    this.url = '',
    this.cookie,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = DownloadStatus.downloading,
  });

  double get progress => totalBytes <= 0 ? 0 : downloadedBytes / totalBytes;

  DownloadItem copyWith({
    int? totalBytes,
    int? downloadedBytes,
    DownloadStatus? status,
  }) => DownloadItem(
    id: id,
    title: title,
    label: label,
    filePath: filePath,
    url: url,
    cookie: cookie,
    totalBytes: totalBytes ?? this.totalBytes,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    status: status ?? this.status,
  );
}

enum DownloadStatus { downloading, paused, completed, failed }

class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  final Dio _dio = Dio();
  final _controller = StreamController<List<DownloadItem>>.broadcast();
  final Map<String, DownloadItem> _items = {};
  final Map<String, CancelToken> _tokens = {};

  Stream<List<DownloadItem>> get stream => _controller.stream;
  List<DownloadItem> get items =>
      _items.values.toList()..sort((a, b) => a.title.compareTo(b.title));

  void _emit() => _controller.add(items);

  Future<Directory> get _downloadDir async {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? '';
      final dir = Directory('$home\\Downloads\\MovieBox Glassy');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    // Android (and fallback): app documents/Downloads.
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/Downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _safeName(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();

  Future<DownloadItem> start({
    required String subjectId,
    required int season,
    required int episode,
    required String title,
    required String url,
    required String qualityLabel,
    String? cookie,
  }) async {
    final id = '$subjectId|$season|$episode';
    final dir = await _downloadDir;
    final ext = url.split('?').first.endsWith('.m3u8') ? '.m3u8' : '.mp4';
    final fileName =
        '${_safeName(title)}${season > 0 || episode > 0 ? ' S${season}E$episode' : ''} $qualityLabel$ext';
    final path = '${dir.path}/$fileName';
    final item = DownloadItem(
      id: id,
      title: title,
      label:
          '${season > 0 || episode > 0 ? 'S$season E$episode · ' : ''}$qualityLabel',
      filePath: path,
      url: url,
      cookie: cookie,
    );
    _items[id] = item;
    _emit();
    unawaited(_run(item, url));
    return item;
  }

  Future<void> _run(DownloadItem item, String url) async {
    final token = CancelToken();
    _tokens[item.id] = token;
    try {
      final file = File(item.filePath);
      var downloaded = await file.exists() ? await file.length() : 0;
      final headers = <String, dynamic>{
        'User-Agent': kUserAgent,
        'Referer': kPlayerReferer,
        if (item.cookie != null && item.cookie!.isNotEmpty)
          'Cookie': item.cookie!,
        if (downloaded > 0) 'Range': 'bytes=$downloaded-',
      };
      await _dio.download(
        url,
        item.filePath,
        cancelToken: token,
        options: Options(headers: headers),
        deleteOnError: false,
        onReceiveProgress: (received, total) {
          // With Range resume, `total` is the remaining bytes.
          final totalBytes = downloaded > 0 ? downloaded + total : total;
          _items[item.id] = item.copyWith(
            totalBytes: totalBytes,
            downloadedBytes: downloaded + received,
          );
          _emit();
        },
      );
      final size = await file.length();
      _items[item.id] = item.copyWith(
        downloadedBytes: size,
        totalBytes: size,
        status: DownloadStatus.completed,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        final cur = _items[item.id];
        if (cur != null) {
          _items[item.id] = cur.copyWith(status: DownloadStatus.paused);
        }
      } else {
        final cur = _items[item.id];
        if (cur != null) {
          _items[item.id] = cur.copyWith(status: DownloadStatus.failed);
        }
      }
    } catch (_) {
      final cur = _items[item.id];
      if (cur != null) {
        _items[item.id] = cur.copyWith(status: DownloadStatus.failed);
      }
    } finally {
      _tokens.remove(item.id);
      _emit();
    }
  }

  /// Pause = cancel the current request, keeping the partial file so a
  /// later resume can continue with Range.
  void pause(String id) => _tokens[id]?.cancel('paused');

  Future<void> resume(String id) async {
    final cur = _items[id];
    if (cur == null || cur.status == DownloadStatus.downloading) return;
    if (cur.url.isEmpty) return; // files from rescan have no source URL
    _items[id] = cur.copyWith(status: DownloadStatus.downloading);
    _emit();
    unawaited(_run(cur, cur.url));
  }

  Future<void> delete(String id) async {
    _tokens[id]?.cancel('deleted');
    final item = _items.remove(id);
    if (item != null) {
      final f = File(item.filePath);
      if (await f.exists()) await f.delete();
    }
    _emit();
  }

  /// Re-scan the downloads folder for files completed in earlier sessions.
  Future<void> rescan() async {
    try {
      final dir = await _downloadDir;
      if (!await dir.exists()) return;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final name = e.path.split(Platform.pathSeparator).last;
        final id = 'file|$name';
        if (_items.containsKey(id)) continue;
        final size = await e.length();
        _items[id] = DownloadItem(
          id: id,
          title: name,
          label: 'Downloaded',
          filePath: e.path,
          totalBytes: size,
          downloadedBytes: size,
          status: DownloadStatus.completed,
        );
      }
      _emit();
    } catch (_) {
      // Best-effort only.
    }
  }
}
