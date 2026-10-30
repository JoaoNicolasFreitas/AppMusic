import 'package:flutter/material.dart';

import '../models/audio_track.dart';
import '../providers/app_controller.dart';
import '../widgets/artwork_tile.dart';
import '../widgets/track_tile.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final playlists = controller.catalog.playlists;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createPlaylist(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nova playlist'),
      ),
      body: playlists.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.queue_music_rounded,
                      size: 54,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Suas playlists começam aqui',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Crie uma lista e adicione músicas da sua biblioteca.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => _createPlaylist(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Criar playlist'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
              children: [
                for (final entry in playlists.entries)
                  Card(
                    child: ListTile(
                      leading: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.queue_music_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Text(entry.key),
                      subtitle: Text('${entry.value.length} músicas'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlaylistDetailScreen(
                            controller: controller,
                            playlistName: entry.key,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _createPlaylist(BuildContext context) async {
    final name = await _askForName(
      context,
      'Criar playlist',
      'Nome da playlist',
    );
    if (name == null) return;
    try {
      await controller.createPlaylist(name);
    } catch (error) {
      controller.reportError(error);
    }
  }
}

class PlaylistDetailScreen extends StatelessWidget {
  const PlaylistDetailScreen({
    required this.controller,
    required this.playlistName,
    super.key,
  });

  final AppController controller;
  final String playlistName;

  @override
  Widget build(BuildContext context) {
    final tracks = controller.tracksInPlaylist(playlistName);
    return Scaffold(
      appBar: AppBar(
        title: Text(playlistName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<_PlaylistAction>(
            onSelected: (action) => _handleAction(context, action),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _PlaylistAction.rename,
                child: Text('Renomear'),
              ),
              PopupMenuItem(
                value: _PlaylistAction.delete,
                child: Text('Excluir playlist'),
              ),
            ],
          ),
        ],
      ),
      body: tracks.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Esta playlist está vazia',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use o menu de uma música na biblioteca para adicioná-la.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Row(
                    children: [
                      ArtworkTile(track: tracks.first, size: 76),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          '${tracks.length} músicas',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _playAll(tracks, context),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Tocar'),
                      ),
                    ],
                  ),
                ),
                for (final track in tracks)
                  TrackTile(
                    controller: controller,
                    track: track,
                    playlistName: playlistName,
                    onPlay: () =>
                        controller.playTrack(track, fromQueue: tracks),
                  ),
              ],
            ),
    );
  }

  Future<void> _playAll(List<AudioTrack> tracks, BuildContext context) async {
    try {
      await controller.playTrack(tracks.first, fromQueue: tracks);
    } catch (error) {
      controller.reportError(error);
    }
  }

  Future<void> _handleAction(
    BuildContext context,
    _PlaylistAction action,
  ) async {
    if (action == _PlaylistAction.rename) {
      final name = await _askForName(
        context,
        'Renomear playlist',
        'Nome da playlist',
        initialValue: playlistName,
      );
      if (name == null) return;
      try {
        await controller.renamePlaylist(playlistName, name);
        if (context.mounted) Navigator.pop(context);
      } catch (error) {
        controller.reportError(error);
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir playlist?'),
        content: const Text('As músicas continuarão no dispositivo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.deletePlaylist(playlistName);
    if (context.mounted) Navigator.pop(context);
  }
}

enum _PlaylistAction { rename, delete }

Future<String?> _askForName(
  BuildContext context,
  String title,
  String label, {
  String initialValue = '',
}) async {
  final textController = TextEditingController(text: initialValue);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: textController,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, textController.text),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  textController.dispose();
  return name;
}
