import 'package:flutter/material.dart';

import '../models/audio_track.dart';
import '../providers/app_controller.dart';
import '../services/audio_library_service.dart';
import '../widgets/track_tile.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _LibrarySort _sort = _LibrarySort.newestFirst;
  final Set<int> _selectedTrackIds = <int>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.controller.tracks.where((track) {
      final query = _query.toLowerCase();
      if (query.isEmpty) return true;
      return track.title.toLowerCase().contains(query) ||
          track.artist.toLowerCase().contains(query) ||
          track.album.toLowerCase().contains(query);
    }).toList();

    final tracks = AudioLibraryService.sortTracks(
      filtered,
      sort: switch (_sort) {
        _LibrarySort.newestFirst => AudioSort.newestFirst,
        _LibrarySort.oldestFirst => AudioSort.oldestFirst,
        _LibrarySort.titleAsc => AudioSort.titleAsc,
        _LibrarySort.titleDesc => AudioSort.titleDesc,
        _LibrarySort.artistAsc => AudioSort.artistAsc,
      },
    );

    final selectionActive = _selectedTrackIds.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value.trim()),
                  decoration: InputDecoration(
                    hintText: 'Buscar música ou artista',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpar busca',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              if (selectionActive)
                IconButton(
                  tooltip: 'Adicionar às playlists',
                  onPressed: () => _addSelectedToPlaylist(tracks),
                  icon: const Icon(Icons.playlist_add_rounded),
                )
              else
                PopupMenuButton<_LibrarySort>(
                  tooltip: 'Ordenar músicas',
                  initialValue: _sort,
                  onSelected: (value) => setState(() => _sort = value),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _LibrarySort.newestFirst,
                      child: Text('Mais recentes primeiro'),
                    ),
                    PopupMenuItem(
                      value: _LibrarySort.oldestFirst,
                      child: Text('Mais antigas primeiro'),
                    ),
                    PopupMenuItem(
                      value: _LibrarySort.titleAsc,
                      child: Text('Nome: A–Z'),
                    ),
                    PopupMenuItem(
                      value: _LibrarySort.titleDesc,
                      child: Text('Nome: Z–A'),
                    ),
                    PopupMenuItem(
                      value: _LibrarySort.artistAsc,
                      child: Text('Artista: A–Z'),
                    ),
                  ],
                  icon: const Icon(Icons.sort_rounded),
                ),
              if (selectionActive)
                IconButton(
                  tooltip: 'Cancelar seleção',
                  onPressed: () => setState(() => _selectedTrackIds.clear()),
                  icon: const Icon(Icons.close_rounded),
                )
              else
                IconButton(
                  tooltip: 'Selecionar músicas',
                  onPressed: () => setState(
                    () => _selectedTrackIds.addAll(
                      tracks.map((track) => track.id),
                    ),
                  ),
                  icon: const Icon(Icons.checklist_rounded),
                ),
            ],
          ),
        ),
        if (selectionActive)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('${_selectedTrackIds.length} selecionadas'),
              ],
            ),
          ),
        Expanded(
          child: widget.controller.isLoading
              ? const Center(child: CircularProgressIndicator())
              : tracks.isEmpty
              ? _EmptyLibrary(
                  denied: widget.controller.permissionDenied,
                  query: _query,
                  onRefresh: widget.controller.refreshLibrary,
                )
              : RefreshIndicator(
                  onRefresh: widget.controller.refreshLibrary,
                  child: ListView.builder(
                    itemCount: tracks.length,
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      final isSelected = _selectedTrackIds.contains(track.id);
                      return TrackTile(
                        controller: widget.controller,
                        track: track,
                        selectionMode: selectionActive,
                        isSelected: isSelected,
                        onToggleSelected: () {
                          setState(() {
                            if (_selectedTrackIds.contains(track.id)) {
                              _selectedTrackIds.remove(track.id);
                            } else {
                              _selectedTrackIds.add(track.id);
                            }
                          });
                        },
                        onPlay: () => widget.controller.playTrack(
                          track,
                          fromQueue: tracks,
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _addSelectedToPlaylist(List<AudioTrack> visibleTracks) async {
    final selectedTracks = visibleTracks
        .where((track) => _selectedTrackIds.contains(track.id))
        .toList();
    if (selectedTracks.isEmpty) return;

    final playlists = widget.controller.catalog.playlists.keys.toList();
    String? choice;
    if (playlists.isEmpty) {
      choice = await _createPlaylistName();
    } else {
      final selection = await showDialog<Object>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Adicionar músicas à playlist'),
          children: [
            for (final playlistName in playlists)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, playlistName),
                child: Text(playlistName),
              ),
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(context, _CreatePlaylistChoice.create),
              child: const Text('Criar nova playlist'),
            ),
          ],
        ),
      );
      if (selection == _CreatePlaylistChoice.create && mounted) {
        choice = await _createPlaylistName();
      } else {
        choice = selection as String?;
      }
    }

    if (choice == null || !mounted) return;

    try {
      if (!widget.controller.catalog.playlists.containsKey(choice)) {
        await widget.controller.createPlaylist(choice);
      }
      final addedCount = await widget.controller.addTracksToPlaylist(
        choice,
        selectedTracks,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$addedCount músicas adicionadas a $choice.')),
        );
      }
      setState(() => _selectedTrackIds.clear());
    } catch (error) {
      widget.controller.reportError(error);
    }
  }

  Future<String?> _createPlaylistName() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nova playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nome da playlist'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.denied,
    required this.query,
    required this.onRefresh,
  });

  final bool denied;
  final String query;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            denied ? Icons.folder_off_outlined : Icons.music_off_rounded,
            size: 52,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            denied
                ? 'Permissão de áudio necessária'
                : query.isNotEmpty
                ? 'Nenhuma música encontrada'
                : 'Nenhuma música local encontrada',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            denied
                ? 'Permita o acesso a arquivos de áudio para ler sua biblioteca.'
                : 'Adicione arquivos de áudio ao dispositivo e atualize a biblioteca.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(denied ? 'Solicitar permissão' : 'Atualizar'),
          ),
        ],
      ),
    ),
  );
}

enum _LibrarySort { newestFirst, oldestFirst, titleAsc, titleDesc, artistAsc }

enum _CreatePlaylistChoice { create }
