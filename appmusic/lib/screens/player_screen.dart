import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../models/audio_track.dart';
import '../providers/app_controller.dart';
import '../services/music_audio_handler.dart';
import '../widgets/artwork_tile.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Tocando agora'),
      actions: [
        IconButton(
          tooltip: 'Fila de reprodução',
          onPressed: () => _showQueue(context),
          icon: const Icon(Icons.queue_music_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: StreamBuilder<MediaItem?>(
        stream: controller.audioHandler.mediaItem,
        builder: (context, itemSnapshot) {
          final item = itemSnapshot.data;
          if (item == null) {
            return const Center(child: Text('Escolha uma música para tocar.'));
          }
          final track = _findTrack(item);
          if (track == null) {
            return const Center(
              child: Text('Esta música não está mais disponível.'),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final coverSize = (constraints.maxWidth - 64)
                  .clamp(220.0, 420.0)
                  .toDouble();
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ArtworkTile(track: track, size: coverSize),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Favoritar',
                              onPressed: () => controller.toggleFavorite(track),
                              icon: Icon(
                                controller.catalog.favorites.contains(
                                      '${track.id}',
                                    )
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _SeekControl(
                          handler: controller.audioHandler,
                          onError: controller.reportError,
                        ),
                        const SizedBox(height: 8),
                        _PlaybackControls(
                          handler: controller.audioHandler,
                          onError: controller.reportError,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );

  AudioTrack? _findTrack(MediaItem item) {
    final id = int.tryParse(item.id);
    for (final track in controller.tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  Future<void> _showQueue(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: StreamBuilder<List<MediaItem>>(
          stream: controller.audioHandler.queue,
          builder: (context, snapshot) {
            final queue = snapshot.data ?? const <MediaItem>[];
            if (queue.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(28),
                child: Text('A fila está vazia.'),
              );
            }
            return ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                  title: Text('Fila de reprodução'),
                  subtitle: Text('Toque em uma faixa para reproduzi-la'),
                ),
                for (var index = 0; index < queue.length; index++)
                  ListTile(
                    leading: const Icon(Icons.music_note_rounded),
                    title: Text(queue[index].title),
                    subtitle: Text(queue[index].artist ?? ''),
                    onTap: () async {
                      try {
                        await controller.audioHandler.skipToQueueItem(index);
                        if (context.mounted) Navigator.pop(context);
                      } catch (error) {
                        controller.reportError(error);
                      }
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SeekControl extends StatelessWidget {
  const _SeekControl({required this.handler, required this.onError});

  final MusicAudioHandler handler;
  final void Function(Object error) onError;

  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
    stream: handler.mediaItem,
    builder: (context, itemSnapshot) {
      final duration = itemSnapshot.data?.duration ?? Duration.zero;
      final max = duration.inMilliseconds
          .toDouble()
          .clamp(1, double.infinity)
          .toDouble();
      return StreamBuilder<Duration>(
        stream: handler.positionStream,
        builder: (context, positionSnapshot) {
          final position =
              (positionSnapshot.data ?? Duration.zero).inMilliseconds;
          final value = position.toDouble().clamp(0, max).toDouble();
          return Column(
            children: [
              Slider(
                min: 0,
                max: max,
                value: value,
                onChanged: duration == Duration.zero
                    ? null
                    : (value) => _seek(value),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(Duration(milliseconds: position))),
                  Text(_formatDuration(duration)),
                ],
              ),
            ],
          );
        },
      );
    },
  );

  Future<void> _seek(double value) async {
    try {
      await handler.seek(Duration(milliseconds: value.round()));
    } catch (error) {
      onError(error);
    }
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.handler, required this.onError});

  final MusicAudioHandler handler;
  final void Function(Object error) onError;

  @override
  Widget build(BuildContext context) => StreamBuilder<PlaybackState>(
    stream: handler.playbackState,
    builder: (context, snapshot) {
      final state = snapshot.data;
      final playing = state?.playing ?? false;
      final shuffleOn = state?.shuffleMode == AudioServiceShuffleMode.all;
      final repeatMode = state?.repeatMode ?? AudioServiceRepeatMode.none;
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: shuffleOn ? 'Desativar aleatório' : 'Ativar aleatório',
            onPressed: () => _run(
              () => handler.setShuffleMode(
                shuffleOn
                    ? AudioServiceShuffleMode.none
                    : AudioServiceShuffleMode.all,
              ),
            ),
            color: shuffleOn ? Theme.of(context).colorScheme.primary : null,
            icon: const Icon(Icons.shuffle_rounded),
          ),
          IconButton(
            tooltip: 'Música anterior',
            onPressed: () => _run(handler.skipToPrevious),
            iconSize: 34,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          FilledButton(
            onPressed: () => _run(playing ? handler.pause : handler.play),
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(18),
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 34,
            ),
          ),
          IconButton(
            tooltip: 'Próxima música',
            onPressed: () => _run(handler.skipToNext),
            iconSize: 34,
            icon: const Icon(Icons.skip_next_rounded),
          ),
          IconButton(
            tooltip: 'Repetir',
            onPressed: () {
              final next = switch (repeatMode) {
                AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
                AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
                _ => AudioServiceRepeatMode.none,
              };
              _run(() => handler.setRepeatMode(next));
            },
            color: repeatMode == AudioServiceRepeatMode.none
                ? null
                : Theme.of(context).colorScheme.primary,
            icon: Icon(
              repeatMode == AudioServiceRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
            ),
          ),
        ],
      );
    },
  );

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      onError(error);
    }
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
