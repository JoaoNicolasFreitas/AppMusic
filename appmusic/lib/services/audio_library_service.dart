import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/audio_track.dart';

enum AudioSort { newestFirst, oldestFirst, titleAsc, titleDesc, artistAsc }

class AudioLibraryService {
  static const _channel = MethodChannel('appmusic/media_library');

  static bool shouldSkipAudioFile(String? fileName) {
    final normalized = fileName?.trim();
    if (normalized == null || normalized.isEmpty) return false;
    return normalized.startsWith(RegExp(r'AUD-', caseSensitive: false));
  }

  static List<AudioTrack> sortTracks(
    List<AudioTrack> tracks, {
    required AudioSort sort,
  }) {
    final sorted = List<AudioTrack>.from(tracks);
    sorted.sort((a, b) {
      switch (sort) {
        case AudioSort.newestFirst:
          return (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0);
        case AudioSort.oldestFirst:
          return (a.dateAdded ?? 0).compareTo(b.dateAdded ?? 0);
        case AudioSort.titleAsc:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case AudioSort.titleDesc:
          return b.title.toLowerCase().compareTo(a.title.toLowerCase());
        case AudioSort.artistAsc:
          return a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      }
    });
    return sorted;
  }

  Future<bool> requestAudioPermission() async {
    var status = await Permission.audio.status;
    if (!status.isGranted) {
      status = await Permission.audio.request();
    }
    if (status.isGranted) return true;

    status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }

  Future<List<AudioTrack>> scan() async {
    final result =
        await _channel.invokeMethod<List<dynamic>>('querySongs') ??
        const <dynamic>[];
    final tracks = <AudioTrack>[];
    final seenIds = <int>{};
    final seenUris = <String>{};

    for (final item in result) {
      final song = Map<Object?, Object?>.from(item as Map);
      final idValue = song['id'];
      final uriValue = song['uri'];
      final displayName =
          song['displayName'] as String? ?? song['fileName'] as String?;
      if (idValue is! num || uriValue is! String || uriValue.isEmpty) {
        throw const FormatException(
          'O MediaStore retornou uma faixa inválida.',
        );
      }
      if (shouldSkipAudioFile(displayName)) {
        continue;
      }

      final id = idValue.toInt();
      if (!seenIds.add(id) || !seenUris.add(uriValue)) continue;
      final title = _cleanMetadata(song['title'] as String?, '');
      tracks.add(
        AudioTrack(
          id: id,
          uri: uriValue,
          title: title.isEmpty ? 'Faixa sem título' : title,
          artist: _cleanMetadata(
            song['artist'] as String?,
            'Artista desconhecido',
          ),
          album: _cleanMetadata(song['album'] as String?, 'Álbum desconhecido'),
          duration: Duration(
            milliseconds: (song['duration'] as num?)?.toInt() ?? 0,
          ),
          dateAdded: (song['dateAdded'] as num?)?.toInt(),
        ),
      );
    }
    return tracks;
  }

  Future<Uint8List?> queryArtwork(int mediaId) =>
      _channel.invokeMethod<Uint8List>('getArtwork', {'id': mediaId});
}

String _cleanMetadata(String? value, String fallback) {
  final normalized = value?.trim();
  if (normalized == null ||
      normalized.isEmpty ||
      normalized.toLowerCase() == '<unknown>') {
    return fallback;
  }
  return normalized;
}
