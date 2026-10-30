import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../models/audio_track.dart';
import '../models/playback_queue.dart';

class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MusicAudioHandler() {
    _player.playbackEventStream.listen(_publishPlaybackState);
    _player.errorStream.listen(_publishPlaybackError);
    _player.currentIndexStream.listen(_publishMediaItem);
    unawaited(_configureAudioSession());
  }

  final AudioPlayer _player = AudioPlayer(maxSkipsOnError: 2);
  PlaybackQueue _queue = PlaybackQueue(const []);
  bool _resumeAfterInterruption = false;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  Future<void> playTracks(List<AudioTrack> tracks, int initialIndex) async {
    final nextQueue = PlaybackQueue(tracks);
    if (nextQueue.isEmpty || !nextQueue.containsIndex(initialIndex)) {
      throw ArgumentError(
        'A fila de reprodução ou a faixa inicial é inválida.',
      );
    }

    _queue = nextQueue;
    final items = _queue.tracks.map((track) => track.toMediaItem()).toList();
    queue.add(items);
    try {
      await _player.setAudioSources(
        _queue.tracks
            .map(
              (track) => AudioSource.uri(
                Uri.parse(track.uri),
                tag: track.toMediaItem(),
              ),
            )
            .toList(),
        initialIndex: initialIndex,
      );
      mediaItem.add(items[initialIndex]);
      await play();
    } on PlayerException catch (error) {
      _publishPlaybackError(error);
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    _resumeAfterInterruption = false;
    await _player.play();
  }

  @override
  Future<void> pause() async {
    _resumeAfterInterruption = false;
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    _resumeAfterInterruption = false;
    await _player.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    await _player.seekToNext();
    await play();
  }

  @override
  Future<void> skipToPrevious() async {
    await _player.seekToPrevious();
    await play();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (!_queue.containsIndex(index)) return;
    await _player.seek(Duration.zero, index: index);
    await play();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
      _ => LoopMode.off,
    });
    await super.setRepeatMode(repeatMode);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _player.setShuffleModeEnabled(
      shuffleMode == AudioServiceShuffleMode.all,
    );
    await super.setShuffleMode(shuffleMode);
  }

  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    session.interruptionEventStream.listen(_handleInterruption);
    session.becomingNoisyEventStream.listen((_) {
      if (_player.playing) {
        unawaited(pause());
      }
    });
  }

  void _handleInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      if (_player.playing) {
        _resumeAfterInterruption = event.type == AudioInterruptionType.pause;
        unawaited(_player.pause());
      }
      return;
    }

    if (_resumeAfterInterruption && event.type == AudioInterruptionType.pause) {
      _resumeAfterInterruption = false;
      unawaited(play());
    }
  }

  void _publishMediaItem(int? index) {
    if (index == null || !_queue.containsIndex(index)) return;
    mediaItem.add(_queue.tracks[index].toMediaItem());
  }

  void _publishPlaybackState(PlaybackEvent event) {
    final isPlaying = _player.playing;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
        repeatMode: playbackState.value.repeatMode,
        shuffleMode: playbackState.value.shuffleMode,
      ),
    );
  }

  void _publishPlaybackError(Object error) {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        playing: false,
        errorCode: error is PlayerException ? error.code : null,
        errorMessage: error.toString(),
      ),
    );
  }
}
