import 'audio_track.dart';

class LibraryCatalog {
  LibraryCatalog({Set<String>? favorites, Map<String, List<String>>? playlists})
    : favorites = favorites ?? <String>{},
      playlists = playlists ?? <String, List<String>>{};

  final Set<String> favorites;
  final Map<String, List<String>> playlists;

  bool toggleFavorite(String trackId) {
    if (!favorites.add(trackId)) {
      favorites.remove(trackId);
      return false;
    }
    return true;
  }

  void createPlaylist(String name) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'O nome não pode ficar vazio.');
    }
    if (playlists.containsKey(normalizedName)) {
      throw ArgumentError.value(
        name,
        'name',
        'Já existe uma playlist com esse nome.',
      );
    }
    playlists[normalizedName] = <String>[];
  }

  void renamePlaylist(String oldName, String newName) {
    final normalizedName = newName.trim();
    if (!playlists.containsKey(oldName)) {
      throw ArgumentError.value(oldName, 'oldName', 'Playlist não encontrada.');
    }
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
        newName,
        'newName',
        'O nome não pode ficar vazio.',
      );
    }
    if (normalizedName != oldName && playlists.containsKey(normalizedName)) {
      throw ArgumentError.value(
        newName,
        'newName',
        'Já existe uma playlist com esse nome.',
      );
    }
    if (normalizedName != oldName) {
      playlists[normalizedName] = playlists.remove(oldName)!;
    }
  }

  void deletePlaylist(String name) {
    playlists.remove(name);
  }

  bool toggleTrack(String playlist, String trackId) {
    final tracks = playlists[playlist];
    if (tracks == null) {
      throw ArgumentError.value(
        playlist,
        'playlist',
        'Playlist não encontrada.',
      );
    }
    if (!tracks.remove(trackId)) {
      tracks.add(trackId);
      return true;
    }
    return false;
  }

  int addTracks(String playlist, Iterable<String> trackIds) {
    final tracks = playlists[playlist];
    if (tracks == null) {
      throw ArgumentError.value(
        playlist,
        'playlist',
        'Playlist não encontrada.',
      );
    }

    final existingIds = tracks.toSet();
    var addedCount = 0;
    for (final trackId in trackIds) {
      if (existingIds.add(trackId)) {
        tracks.add(trackId);
        addedCount++;
      }
    }
    return addedCount;
  }

  List<AudioTrack> tracksInPlaylist(
    String playlist,
    Iterable<AudioTrack> availableTracks,
  ) {
    final trackIds = playlists[playlist] ?? const <String>[];
    final tracksById = <String, AudioTrack>{
      for (final track in availableTracks) '${track.id}': track,
    };
    final orderedTracks = <AudioTrack>[];
    for (final trackId in trackIds) {
      final track = tracksById[trackId];
      if (track != null) orderedTracks.add(track);
    }
    return orderedTracks;
  }

  void removeTrack(String trackId) {
    favorites.remove(trackId);
    for (final tracks in playlists.values) {
      tracks.remove(trackId);
    }
  }
}
