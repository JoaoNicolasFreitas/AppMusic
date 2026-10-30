enum DownloadJobStatus { queued, running, paused, completed, failed, cancelled }

class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.sourceUrl,
    required this.title,
    required this.status,
    required this.progress,
    required this.createdAt,
    this.resolvedUrl,
    this.extension,
    this.downloadId,
    this.bytesDownloaded = 0,
    this.speedBytesPerSecond = 0,
    this.remainingSeconds,
    this.totalBytes,
    this.outputUri,
    this.mediaId,
    this.error,
    this.artist,
    this.artworkUrl,
  });

  final int id;
  final String sourceUrl;
  final String title;
  final DownloadJobStatus status;
  final double progress;
  final int createdAt;
  final String? resolvedUrl;
  final String? extension;
  final int? downloadId;
  final int bytesDownloaded;
  final int speedBytesPerSecond;
  final int? remainingSeconds;
  final int? totalBytes;
  final String? outputUri;
  final int? mediaId;
  final String? error;
  final String? artist;
  final String? artworkUrl;

  bool get isTerminal =>
      status == DownloadJobStatus.completed ||
      status == DownloadJobStatus.failed ||
      status == DownloadJobStatus.cancelled;

  DownloadJob copyWith({
    DownloadJobStatus? status,
    double? progress,
    Object? resolvedUrl = _unchanged,
    Object? extension = _unchanged,
    int? downloadId,
    int? bytesDownloaded,
    int? speedBytesPerSecond,
    Object? remainingSeconds = _unchanged,
    Object? totalBytes = _unchanged,
    Object? outputUri = _unchanged,
    Object? mediaId = _unchanged,
    Object? error = _unchanged,
    Object? artist = _unchanged,
    Object? artworkUrl = _unchanged,
  }) => DownloadJob(
    id: id,
    sourceUrl: sourceUrl,
    title: title,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    createdAt: createdAt,
    resolvedUrl: identical(resolvedUrl, _unchanged)
        ? this.resolvedUrl
        : resolvedUrl as String?,
    extension: identical(extension, _unchanged)
        ? this.extension
        : extension as String?,
    downloadId: downloadId ?? this.downloadId,
    bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
    speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
    remainingSeconds: identical(remainingSeconds, _unchanged)
        ? this.remainingSeconds
        : remainingSeconds as int?,
    totalBytes: identical(totalBytes, _unchanged)
        ? this.totalBytes
        : totalBytes as int?,
    outputUri: identical(outputUri, _unchanged)
        ? this.outputUri
        : outputUri as String?,
    mediaId: identical(mediaId, _unchanged) ? this.mediaId : mediaId as int?,
    error: identical(error, _unchanged) ? this.error : error as String?,
    artist: identical(artist, _unchanged) ? this.artist : artist as String?,
    artworkUrl: identical(artworkUrl, _unchanged)
        ? this.artworkUrl
        : artworkUrl as String?,
  );

  static const _unchanged = Object();
}
