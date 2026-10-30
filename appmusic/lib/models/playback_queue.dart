import 'audio_track.dart';

class PlaybackQueue {
  PlaybackQueue(Iterable<AudioTrack> tracks)
    : tracks = List<AudioTrack>.unmodifiable(tracks);

  final List<AudioTrack> tracks;

  bool get isEmpty => tracks.isEmpty;

  bool containsIndex(int index) => index >= 0 && index < tracks.length;

  int indexOfId(int trackId) =>
      tracks.indexWhere((track) => track.id == trackId);
}
