import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/download_job.dart';
import '../models/download_preview.dart';
import 'download_resolver.dart';

typedef DownloadLibraryRefresh = Future<void> Function();

class DownloadService extends ChangeNotifier {
  DownloadService({this.onCompleted});

  static const _channel = MethodChannel('appmusic/media_downloader');
  static const _events = EventChannel('appmusic/media_downloader/events');

  final DownloadLibraryRefresh? onCompleted;
  final DownloadResolver _resolver = DownloadResolver();
  Database? _database;
  StreamSubscription<dynamic>? _eventSubscription;
  List<DownloadJob> jobs = const [];
  final Set<int> _cancelledIds = <int>{};
  bool _isDownloading = false;

  bool get isInitialized => _database != null;

  Future<void> initialize() async {
    if (_database != null) return;
    _database = await openDatabase(
      'appmusic_downloads.db',
      version: 5,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE download_jobs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_url TEXT NOT NULL,
            title TEXT NOT NULL,
            status INTEGER NOT NULL,
            progress REAL NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            resolved_url TEXT,
            extension TEXT,
            download_id INTEGER,
            bytes_downloaded INTEGER NOT NULL DEFAULT 0,
            speed_bytes_per_second INTEGER NOT NULL DEFAULT 0,
            remaining_seconds INTEGER,
            total_bytes INTEGER,
            output_uri TEXT,
            media_id INTEGER,
            error TEXT,
            artist TEXT,
            artwork_url TEXT,
            UNIQUE(source_url)
          )
        ''');
        await database.execute(
          'CREATE INDEX download_jobs_status_index '
          'ON download_jobs(status)',
        );
      },
      onUpgrade: (database, oldVersion, _) async {
        if (oldVersion < 2) {
          await database.execute(
            'ALTER TABLE download_jobs ADD COLUMN resolved_url TEXT',
          );
          await database.execute(
            'ALTER TABLE download_jobs ADD COLUMN extension TEXT',
          );
        }
        if (oldVersion < 3) {
          await database.execute(
            'ALTER TABLE download_jobs ADD COLUMN speed_bytes_per_second INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE download_jobs ADD COLUMN remaining_seconds INTEGER',
          );
        }
        if (oldVersion < 4) {
          await database.execute(
            'ALTER TABLE download_jobs ADD COLUMN artist TEXT',
          );
        }
        if (oldVersion < 5) {
          await database.execute(
            'ALTER TABLE download_jobs ADD COLUMN artwork_url TEXT',
          );
        }
      },
    );
    jobs = await _loadJobs();

    // Reset any interrupted running jobs back to queued
    for (final job in jobs) {
      if (job.status == DownloadJobStatus.running) {
        await _updateJob(job.id, status: DownloadJobStatus.queued);
      }
    }

    _eventSubscription = _events.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: _handleNativeError,
    );

    unawaited(_pumpQueue());
    notifyListeners();
  }

  bool supportsSource(String sourceUrl) {
    final trimmed = sourceUrl.trim();
    if (_resolver.extractVideoId(trimmed) != null) return true;
    final uri = Uri.tryParse(trimmed);
    return uri != null &&
        uri.host.isNotEmpty &&
        (uri.isScheme('https') || uri.isScheme('http'));
  }

  Future<DownloadPreview> resolve(String sourceUrl) =>
      _resolver.resolve(sourceUrl);

  Future<int?> enqueue(
    String sourceUrl,
    DownloadAudioOption option, {
    String? title,
    String? artist,
    String? artworkUrl,
  }) async {
    final normalizedUrl = sourceUrl.trim();
    final db = _database;
    if (db == null) throw StateError('O gerenciador de downloads não iniciou.');

    final existing = jobs.where((job) => job.sourceUrl == normalizedUrl);
    if (existing.isNotEmpty) {
      final job = existing.first;
      if (!job.isTerminal) return job.id;
      await db.delete('download_jobs', where: 'id = ?', whereArgs: [job.id]);
    }

    final id = await db.insert('download_jobs', {
      'source_url': normalizedUrl,
      'title': title?.trim().isNotEmpty == true
          ? title!.trim()
          : _titleFromUrl(Uri.tryParse(normalizedUrl)),
      'status': DownloadJobStatus.queued.index,
      'progress': 0.0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'resolved_url': option.downloadUrl,
      'extension': option.extension,
      'artist': artist,
      'artwork_url': artworkUrl,
    });
    _cancelledIds.remove(id);
    jobs = await _loadJobs();
    notifyListeners();
    unawaited(_pumpQueue());
    return id;
  }

  Future<void> cancel(int jobId) async {
    _cancelledIds.add(jobId);
    final job = _job(jobId);
    if (job.downloadId != null) {
      await _cancelNative(job);
    }
    if (job.status != DownloadJobStatus.running) {
      await _updateJob(
        jobId,
        status: DownloadJobStatus.cancelled,
        progress: 0,
        speedBytesPerSecond: 0,
        remainingSeconds: null,
        error: null,
      );
    }
    unawaited(_pumpQueue());
  }

  Future<void> retry(int jobId) async {
    final job = _job(jobId);
    if (job.status != DownloadJobStatus.failed &&
        job.status != DownloadJobStatus.cancelled) {
      return;
    }
    _cancelledIds.remove(jobId);
    await _updateJob(
      jobId,
      status: DownloadJobStatus.queued,
      progress: 0,
      bytesDownloaded: 0,
      speedBytesPerSecond: 0,
      remainingSeconds: null,
      totalBytes: null,
      outputUri: null,
      mediaId: null,
      error: null,
    );
    unawaited(_pumpQueue());
  }

  Future<void> remove(int jobId) async {
    final job = _job(jobId);
    if (!job.isTerminal) {
      _cancelledIds.add(jobId);
      if (job.downloadId != null) await _cancelNative(job);
    }
    await _database?.delete(
      'download_jobs',
      where: 'id = ?',
      whereArgs: [jobId],
    );
    jobs = await _loadJobs();
    notifyListeners();
  }

  Future<void> clearCompleted() async {
    await _database?.delete(
      'download_jobs',
      where: 'status = ?',
      whereArgs: [DownloadJobStatus.completed.index],
    );
    jobs = await _loadJobs();
    notifyListeners();
  }

  Future<void> _pumpQueue() async {
    final db = _database;
    if (db == null || _isDownloading) return;

    final next = jobs
        .where((job) => job.status == DownloadJobStatus.queued)
        .toList()
        .firstOrNull;
    if (next == null) return;

    _isDownloading = true;
    await _updateJob(
      next.id,
      status: DownloadJobStatus.running,
      error: null,
    );

    try {
      await _executeDownload(next);
    } catch (error) {
      if (!_cancelledIds.contains(next.id)) {
        await _updateJob(
          next.id,
          status: DownloadJobStatus.failed,
          error: error.toString(),
        );
      }
    } finally {
      _isDownloading = false;
      unawaited(_pumpQueue());
    }
  }

  Future<void> _executeDownload(DownloadJob job) async {
    if (_cancelledIds.contains(job.id)) {
      await _updateJob(
        job.id,
        status: DownloadJobStatus.cancelled,
        progress: 0,
        speedBytesPerSecond: 0,
        remainingSeconds: null,
        error: null,
      );
      return;
    }

    String? targetUrl = job.resolvedUrl;
    String extension = job.extension ?? 'mp3';

    // Se a URL salva não for um link HTTP válido, resolve novamente
    if (targetUrl == null || !targetUrl.startsWith('http')) {
      final preview = await _resolver.resolve(job.sourceUrl);
      final opt = preview.options.firstWhere(
        (o) => o.extension == extension,
        orElse: () => preview.options.first,
      );
      targetUrl = opt.downloadUrl;
      extension = opt.extension;
      await _updateJob(
        job.id,
        resolvedUrl: targetUrl,
        artist: preview.artist ?? job.artist,
        artworkUrl: preview.artworkUrl ?? job.artworkUrl,
      );
    }

    try {
      await _downloadHttpStream(job, targetUrl, extension);
    } catch (error) {
      // Auto-recuperação: se a URL expirou ou deu erro de autenticação (ex: 403),
      // re-resolve uma URL nova e tenta novamente antes de falhar
      if (!_cancelledIds.contains(job.id)) {
        try {
          final freshPreview = await _resolver.resolve(job.sourceUrl);
          final freshOpt = freshPreview.options.firstWhere(
            (o) => o.extension == extension,
            orElse: () => freshPreview.options.first,
          );
          targetUrl = freshOpt.downloadUrl;
          extension = freshOpt.extension;
          await _updateJob(
            job.id,
            resolvedUrl: targetUrl,
            artist: freshPreview.artist ?? job.artist,
            artworkUrl: freshPreview.artworkUrl ?? job.artworkUrl,
          );
          await _downloadHttpStream(job, targetUrl, extension);
          return;
        } catch (_) {
          // Se falhar na segunda tentativa, propaga o erro original
          rethrow;
        }
      }
      rethrow;
    }
  }

  Future<void> _downloadHttpStream(
    DownloadJob job,
    String downloadUrl,
    String extension,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(minutes: 2);
    File? artworkTempFile;
    try {
      // Baixa a capa do YouTube em paralelo para salvar na biblioteca
      if (job.artworkUrl != null && job.artworkUrl!.startsWith('http')) {
        try {
          final artReq = await client.getUrl(Uri.parse(job.artworkUrl!));
          final artResp = await artReq.close().timeout(const Duration(seconds: 6));
          if (artResp.statusCode == 200) {
            final tempDir = await getTemporaryDirectory();
            artworkTempFile = File(
              '${tempDir.path}/appmusic_art_${job.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
            );
            final artSink = artworkTempFile.openWrite();
            await artResp.pipe(artSink);
          }
        } catch (_) {
          artworkTempFile = null;
        }
      }

      final request = await client.getUrl(Uri.parse(downloadUrl));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      );
      final response = await request.close();
      if (response.statusCode >= 400) {
        throw HttpException(
          'HTTP ${response.statusCode} (${response.reasonPhrase}) ao baixar arquivo.',
        );
      }
      final totalBytes =
          response.contentLength > 0 ? response.contentLength : null;

      await _streamToFile(
        job: job,
        byteStream: response,
        totalBytes: totalBytes,
        extension: extension,
        artworkFilePath: artworkTempFile?.path,
      );
    } finally {
      client.close();
      try {
        if (artworkTempFile != null && await artworkTempFile.exists()) {
          await artworkTempFile.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _streamToFile({
    required DownloadJob job,
    required Stream<List<int>> byteStream,
    required int? totalBytes,
    required String extension,
    String? artworkFilePath,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/appmusic_dl_${job.id}_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    final sink = tempFile.openWrite();

    var downloaded = 0;
    var lastMeasuredTime = DateTime.now().millisecondsSinceEpoch;
    var lastMeasuredBytes = 0;
    var speed = 0;
    int? remainingSeconds;
    var lastNotifyTime = 0;

    try {
      await for (final chunk in byteStream) {
        if (_cancelledIds.contains(job.id)) {
          await sink.close();
          if (await tempFile.exists()) await tempFile.delete();
          await _updateJob(
            job.id,
            status: DownloadJobStatus.cancelled,
            progress: 0,
            speedBytesPerSecond: 0,
            remainingSeconds: null,
            error: null,
          );
          return;
        }

        sink.add(chunk);
        downloaded += chunk.length;

        final now = DateTime.now().millisecondsSinceEpoch;
        final elapsed = now - lastMeasuredTime;
        if (elapsed >= 800) {
          speed = ((downloaded - lastMeasuredBytes) * 1000 ~/ elapsed);
          lastMeasuredBytes = downloaded;
          lastMeasuredTime = now;
          if (speed > 0 && totalBytes != null && totalBytes > downloaded) {
            remainingSeconds = (totalBytes - downloaded) ~/ speed;
          }
        }

        if (now - lastNotifyTime >= 350) {
          lastNotifyTime = now;
          final progress = totalBytes != null && totalBytes > 0
              ? (downloaded / totalBytes).clamp(0.0, 1.0)
              : 0.0;
          await _updateJob(
            job.id,
            status: DownloadJobStatus.running,
            progress: progress,
            bytesDownloaded: downloaded,
            totalBytes: totalBytes,
            speedBytesPerSecond: speed,
            remainingSeconds: remainingSeconds,
          );
        }
      }
      await sink.flush();
      await sink.close();

      if (_cancelledIds.contains(job.id)) {
        if (await tempFile.exists()) await tempFile.delete();
        await _updateJob(
          job.id,
          status: DownloadJobStatus.cancelled,
          progress: 0,
          speedBytesPerSecond: 0,
          remainingSeconds: null,
          error: null,
        );
        return;
      }

      // Importar para a biblioteca do MediaStore via ponte nativa
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'importDownloadedAudio',
        {
          'filePath': tempFile.path,
          'title': job.title,
          'artist': job.artist ?? 'Artista desconhecido',
          'album': 'Downloads',
          'extension': extension,
          'artworkPath': artworkFilePath,
        },
      );

      final mediaId = (result?['mediaId'] as num?)?.toInt();
      final outputUri = result?['outputUri'] as String?;

      await _updateJob(
        job.id,
        status: DownloadJobStatus.completed,
        progress: 1.0,
        bytesDownloaded: downloaded,
        totalBytes: totalBytes ?? downloaded,
        speedBytesPerSecond: 0,
        remainingSeconds: null,
        outputUri: outputUri,
        mediaId: mediaId,
        error: null,
      );

      await onCompleted?.call();
    } catch (e) {
      await sink.close();
      if (await tempFile.exists()) await tempFile.delete();
      rethrow;
    }
  }

  Future<void> _cancelNative(DownloadJob job) async {
    final downloadId = job.downloadId;
    if (downloadId == null) return;
    try {
      await _channel.invokeMethod<void>('cancelDownload', downloadId);
    } catch (_) {}
  }

  Future<void> _handleNativeEvent(dynamic event) async {
    if (event is! Map) return;
    final downloadId = (event['downloadId'] as num?)?.toInt();
    if (downloadId == null) return;
    final jobIndex = jobs.indexWhere((job) => job.downloadId == downloadId);
    if (jobIndex < 0) return;
    final job = jobs[jobIndex];
    final status = event['status'] as String?;
    if (status == 'running' || status == 'paused') {
      await _updateJob(
        job.id,
        status: status == 'paused'
            ? DownloadJobStatus.paused
            : DownloadJobStatus.running,
        bytesDownloaded: (event['bytesDownloaded'] as num?)?.toInt() ?? 0,
        speedBytesPerSecond:
            (event['speedBytesPerSecond'] as num?)?.toInt() ?? 0,
        remainingSeconds: (event['remainingSeconds'] as num?)?.toInt(),
        totalBytes: (event['totalBytes'] as num?)?.toInt(),
        progress: (event['progress'] as num?)?.toDouble() ?? 0,
      );
      return;
    }
    if (status == 'completed') {
      await _updateJob(
        job.id,
        status: DownloadJobStatus.completed,
        progress: 1,
        outputUri: event['outputUri'] as String?,
        mediaId: (event['mediaId'] as num?)?.toInt(),
      );
      await onCompleted?.call();
      return;
    }
    if (status == 'failed') {
      await _updateJob(
        job.id,
        status: DownloadJobStatus.failed,
        error: event['error'] as String?,
      );
    }
  }

  void _handleNativeError(Object error) {
    debugPrint('Erro no canal de downloads: $error');
  }

  DownloadJob _job(int id) {
    for (final job in jobs) {
      if (job.id == id) return job;
    }
    throw StateError('Download não encontrado.');
  }

  Future<void> _updateJob(
    int id, {
    DownloadJobStatus? status,
    double? progress,
    int? downloadId,
    Object? resolvedUrl = _unchanged,
    int? bytesDownloaded,
    int? speedBytesPerSecond,
    Object? remainingSeconds = _unchanged,
    int? totalBytes,
    String? outputUri,
    int? mediaId,
    String? error,
    Object? artist = _unchanged,
    Object? artworkUrl = _unchanged,
  }) async {
    final job = _job(id);
    final values = <String, Object?>{'error': error};
    if (!identical(resolvedUrl, _unchanged)) {
      values['resolved_url'] = resolvedUrl as String?;
    }
    if (!identical(artist, _unchanged)) {
      values['artist'] = artist as String?;
    }
    if (!identical(artworkUrl, _unchanged)) {
      values['artwork_url'] = artworkUrl as String?;
    }
    if (status != null) values['status'] = status.index;
    if (progress != null) values['progress'] = progress;
    if (downloadId != null) values['download_id'] = downloadId;
    if (bytesDownloaded != null) {
      values['bytes_downloaded'] = bytesDownloaded;
    }
    if (speedBytesPerSecond != null) {
      values['speed_bytes_per_second'] = speedBytesPerSecond;
    }
    if (!identical(remainingSeconds, _unchanged)) {
      values['remaining_seconds'] = remainingSeconds as int?;
    }
    if (totalBytes != null) values['total_bytes'] = totalBytes;
    if (outputUri != null) values['output_uri'] = outputUri;
    if (mediaId != null) values['media_id'] = mediaId;
    await _database?.update(
      'download_jobs',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
    var updated = job.copyWith(
      status: status,
      progress: progress,
      downloadId: downloadId,
      bytesDownloaded: bytesDownloaded,
      speedBytesPerSecond: speedBytesPerSecond,
      totalBytes: totalBytes,
      outputUri: outputUri,
      mediaId: mediaId,
      error: error,
    );
    if (!identical(resolvedUrl, _unchanged)) {
      updated = updated.copyWith(resolvedUrl: resolvedUrl);
    }
    if (!identical(remainingSeconds, _unchanged)) {
      updated = updated.copyWith(remainingSeconds: remainingSeconds);
    }
    if (!identical(artist, _unchanged)) {
      updated = updated.copyWith(artist: artist);
    }
    if (!identical(artworkUrl, _unchanged)) {
      updated = updated.copyWith(artworkUrl: artworkUrl);
    }
    jobs = jobs
        .map((candidate) => candidate.id == id ? updated : candidate)
        .toList();
    notifyListeners();
  }

  Future<List<DownloadJob>> _loadJobs() async {
    final rows = await _database!.query(
      'download_jobs',
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(_jobFromRow).toList(growable: false);
  }

  DownloadJob _jobFromRow(Map<String, Object?> row) => DownloadJob(
    id: row['id'] as int,
    sourceUrl: row['source_url'] as String,
    title: row['title'] as String,
    status: DownloadJobStatus.values[row['status'] as int],
    progress: (row['progress'] as num).toDouble(),
    createdAt: row['created_at'] as int,
    resolvedUrl: row['resolved_url'] as String?,
    extension: row['extension'] as String?,
    downloadId: row['download_id'] as int?,
    bytesDownloaded: (row['bytes_downloaded'] as num?)?.toInt() ?? 0,
    speedBytesPerSecond: (row['speed_bytes_per_second'] as num?)?.toInt() ?? 0,
    remainingSeconds: (row['remaining_seconds'] as num?)?.toInt(),
    totalBytes: (row['total_bytes'] as num?)?.toInt(),
    outputUri: row['output_uri'] as String?,
    mediaId: (row['media_id'] as num?)?.toInt(),
    error: row['error'] as String?,
    artist: row['artist'] as String?,
    artworkUrl: row['artwork_url'] as String?,
  );

  static const _unchanged = Object();

  String _titleFromUrl(Uri? uri) {
    if (uri == null) return 'Música baixada';
    final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    var title = Uri.decodeComponent(segment);
    title = title.replaceAll(RegExp(r'\.[^.]+$'), '').trim();
    return title.isEmpty ? 'Música baixada' : title;
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}
