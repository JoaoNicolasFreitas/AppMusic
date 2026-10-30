import 'package:audio_service/audio_service.dart';

class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.uri,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.dateAdded,
  });

  final int id;
  final String uri;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final int? dateAdded;

  MediaItem toMediaItem() => MediaItem(
    id: id.toString(),
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    artUri: Uri.parse(uri),
    extras: {'uri': uri, 'mediaId': id, 'loadThumbnailUri': uri},
  );
}
