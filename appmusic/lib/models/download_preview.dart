class DownloadAudioOption {
  const DownloadAudioOption({
    required this.id,
    required this.label,
    required this.downloadUrl,
    required this.extension,
    required this.estimatedBytes,
  });

  final String id;
  final String label;
  final String downloadUrl;
  final String extension;
  final int? estimatedBytes;
}

class DownloadPreview {
  const DownloadPreview({
    required this.sourceUrl,
    required this.title,
    required this.isYouTube,
    this.artist,
    this.artworkUrl,
    this.duration,
    this.options = const [],
  });

  final String sourceUrl;
  final String title;
  final bool isYouTube;
  final String? artist;
  final String? artworkUrl;
  final Duration? duration;
  final List<DownloadAudioOption> options;
}
