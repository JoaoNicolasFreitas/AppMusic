import 'package:flutter/material.dart';

import '../models/audio_track.dart';
import '../providers/app_controller.dart';
import 'artwork_tile.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({
    required this.controller,
    required this.track,
    required this.onPlay,
    this.playlistName,
    this.selectionMode = false,
    this.isSelected = false,
    this.onToggleSelected,
    super.key,
  });

  final AppController controller;
  final AudioTrack track;
  final Future<void> Function() onPlay;
  final String? playlistName;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelected;

  @override
  Widget build(BuildContext context) {
    final isFavorite = controller.catalog.favorites.contains('${track.id}');
    final trailing = selectionMode
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: isFavorite
                    ? 'Remover dos favoritos'
                    : 'Adicionar aos favoritos',
                onPressed: () =>
                    _run(context, () => controller.toggleFavorite(track)),
                icon: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFavorite
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              PopupMenuButton<_TrackAction>(
                tooltip: 'Mais opções',
                onSelected: (action) => _handleAction(context, action),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _TrackAction.playlist,
                    child: Text(
                      playlistName == null
                          ? 'Adicionar à playlist'
                          : 'Remover da playlist',
                    ),
                  ),
                  const PopupMenuItem(
                    value: _TrackAction.delete,
                    child: Text('Excluir do dispositivo'),
                  ),
                ],
              ),
            ],
          );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
      leading: selectionMode
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => onToggleSelected?.call(),
            )
          : ArtworkTile(track: track, size: 52),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${track.artist} · ${_formatDuration(track.duration)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        if (selectionMode) {
          onToggleSelected?.call();
          return;
        }
        _run(context, onPlay);
      },
      trailing: trailing,
    );
  }

  Future<void> _handleAction(BuildContext context, _TrackAction action) async {
    if (action == _TrackAction.playlist) {
      if (playlistName != null) {
        await _run(
          context,
          () => controller.toggleTrackInPlaylist(playlistName!, track),
        );
        return;
      }
      await _choosePlaylist(context);
    } else {
      await _confirmDelete(context);
    }
  }

  Future<void> _choosePlaylist(BuildContext context) async {
    final playlists = controller.catalog.playlists.keys.toList();
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crie uma playlist primeiro.')),
      );
      return;
    }
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Adicionar à playlist'),
        children: [
          for (final name in playlists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, name),
              child: Text(name),
            ),
        ],
      ),
    );
    if (chosen != null && context.mounted) {
      await _run(
        context,
        () => controller.toggleTrackInPlaylist(chosen, track),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir música?'),
        content: Text(
          '"${track.title}" será removida do armazenamento do dispositivo. '
          'O Android poderá solicitar uma segunda confirmação.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(context, () async {
      final deleted = await controller.deleteTrack(track);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleted
                ? 'Música excluída.'
                : 'A exclusão foi cancelada; a música foi mantida.',
          ),
        ),
      );
    });
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      controller.reportError(error);
    }
  }
}

enum _TrackAction { playlist, delete }

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
