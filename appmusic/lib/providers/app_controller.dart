import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/audio_track.dart';
import '../models/download_job.dart';
import '../models/library_catalog.dart';
import '../services/audio_library_service.dart';
import '../services/download_service.dart';
import '../services/media_deletion_service.dart';
import '../services/music_audio_handler.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.audioHandler,
    AudioLibraryService? libraryService,
    MediaDeletionService? deletionService,
    SharedPreferencesAsync? preferences,
    DownloadService? downloadService,
  }) : downloadService = downloadService ?? DownloadService(),
       _libraryService = libraryService ?? AudioLibraryService(),
       _deletionService = deletionService ?? MediaDeletionService(),
       _preferences = preferences ?? SharedPreferencesAsync() {
    this.downloadService.addListener(_onDownloadsChanged);
  }

  final MusicAudioHandler audioHandler;
  final DownloadService downloadService;
  final AudioLibraryService _libraryService;
  final MediaDeletionService _deletionService;
  final SharedPreferencesAsync _preferences;

  final LibraryCatalog catalog = LibraryCatalog();
  List<AudioTrack> tracks = const [];
  bool isLoading = false;
  bool permissionDenied = false;
  bool isDarkTheme = true;
  String? errorMessage;

  List<AudioTrack> get favorites => tracks
      .where((track) => catalog.favorites.contains('${track.id}'))
      .toList();

  Future<void> initialize() async {
    await _loadSavedData();
    await downloadService.initialize();
    await refreshLibrary();
  }

  void _onDownloadsChanged() {
    if (downloadService.jobs.any(
      (job) => job.status == DownloadJobStatus.completed && job.mediaId != null,
    )) {
      unawaited(refreshLibrary());
    }
  }

  Future<void> refreshLibrary() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      if (!await _libraryService.requestAudioPermission()) {
        permissionDenied = true;
        return;
      }
      tracks = await _libraryService.scan();
      permissionDenied = false;
    } catch (error) {
      errorMessage = 'Não foi possível ler a biblioteca: $error';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleFavorite(AudioTrack track) async {
    catalog.toggleFavorite('${track.id}');
    notifyListeners();
    await _persistSavedData();
  }

  Future<void> createPlaylist(String name) async {
    catalog.createPlaylist(name);
    notifyListeners();
    await _persistSavedData();
  }

  Future<void> renamePlaylist(String oldName, String newName) async {
    catalog.renamePlaylist(oldName, newName);
    notifyListeners();
    await _persistSavedData();
  }

  Future<void> deletePlaylist(String name) async {
    catalog.deletePlaylist(name);
    notifyListeners();
    await _persistSavedData();
  }

  Future<void> toggleTrackInPlaylist(String playlist, AudioTrack track) async {
    catalog.toggleTrack(playlist, '${track.id}');
    notifyListeners();
    await _persistSavedData();
  }

  Future<int> addTracksToPlaylist(
    String playlist,
    Iterable<AudioTrack> tracksToAdd,
  ) async {
    final addedCount = catalog.addTracks(
      playlist,
      tracksToAdd.map((track) => '${track.id}'),
    );
    if (addedCount == 0) return 0;
    await _persistSavedData();
    notifyListeners();
    return addedCount;
  }

  List<AudioTrack> tracksInPlaylist(String playlist) {
    return catalog.tracksInPlaylist(playlist, tracks);
  }

  Future<bool> deleteTrack(AudioTrack track) async {
    final deleted = await _deletionService.delete(track.id);
    if (!deleted) return false;
    catalog.removeTrack('${track.id}');
    await _persistSavedData();
    await refreshLibrary();
    return true;
  }

  Future<void> playTrack(
    AudioTrack track, {
    List<AudioTrack>? fromQueue,
  }) async {
    final source = fromQueue ?? tracks;
    final index = source.indexWhere((item) => item.id == track.id);
    if (index < 0) {
      throw StateError('A música não está mais disponível na biblioteca.');
    }
    await audioHandler.playTracks(source, index);
  }

  Future<void> toggleTheme() async {
    isDarkTheme = !isDarkTheme;
    notifyListeners();
    try {
      await _preferences.setBool('dark_theme', isDarkTheme);
    } catch (error) {
      reportError('Não foi possível salvar o tema: $error');
    }
  }

  void reportError(Object error) {
    errorMessage = error.toString();
    notifyListeners();
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    downloadService.removeListener(_onDownloadsChanged);
    downloadService.dispose();
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    try {
      isDarkTheme = await _preferences.getBool('dark_theme') ?? true;
      final favoriteData = await _preferences.getString('favorites');
      final playlistData = await _preferences.getString('playlists');
      if (favoriteData != null) {
        final decoded = jsonDecode(favoriteData);
        if (decoded is! List) {
          throw const FormatException('Favoritos inválidos.');
        }
        catalog.favorites.addAll(decoded.whereType<String>());
      }
      if (playlistData != null) {
        final decoded = jsonDecode(playlistData);
        if (decoded is! Map) {
          throw const FormatException('Playlists inválidas.');
        }
        for (final entry in decoded.entries) {
          if (entry.key is String && entry.value is List) {
            catalog.playlists[entry.key as String] = (entry.value as List)
                .whereType<String>()
                .toList();
          }
        }
      }
    } catch (error) {
      errorMessage = 'Não foi possível carregar os dados salvos: $error';
    }
  }

  Future<void> _persistSavedData() async {
    try {
      await _preferences.setString(
        'favorites',
        jsonEncode(catalog.favorites.toList()),
      );
      await _preferences.setString('playlists', jsonEncode(catalog.playlists));
    } catch (error) {
      errorMessage = 'Não foi possível salvar suas alterações: $error';
      notifyListeners();
      rethrow;
    }
  }
}
