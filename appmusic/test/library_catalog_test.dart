import 'package:flutter_test/flutter_test.dart';

import 'package:appmusic/models/audio_track.dart';
import 'package:appmusic/models/library_catalog.dart';
import 'package:appmusic/models/playback_queue.dart';
import 'package:appmusic/services/audio_library_service.dart';

void main() {
  group('PlaybackQueue', () {
    test('preserves play order and finds track positions', () {
      final queue = PlaybackQueue([_track(8), _track(3), _track(21)]);

      expect(queue.tracks.map((track) => track.id), [8, 3, 21]);
      expect(queue.indexOfId(3), 1);
      expect(queue.indexOfId(99), -1);
      expect(queue.containsIndex(2), isTrue);
      expect(queue.containsIndex(3), isFalse);
    });

    test('does not expose a mutable queue list', () {
      final queue = PlaybackQueue([_track(1)]);

      expect(() => queue.tracks.add(_track(2)), throwsUnsupportedError);
    });
  });

  group('AudioLibraryService', () {
    test('filters AUD- files without changing valid names', () {
      expect(AudioLibraryService.shouldSkipAudioFile('AUD-1234.mp3'), isTrue);
      expect(AudioLibraryService.shouldSkipAudioFile('aud-1234.ogg'), isTrue);
      expect(AudioLibraryService.shouldSkipAudioFile('Aud-1234.m4a'), isTrue);
      expect(AudioLibraryService.shouldSkipAudioFile('Song Name.mp3'), isFalse);
    });

    test('sorts recent and older tracks correctly', () {
      final tracks = [
        _track(1, dateAdded: 200),
        _track(2, dateAdded: 500),
        _track(3, dateAdded: 300),
      ];

      expect(
        AudioLibraryService.sortTracks(
          tracks,
          sort: AudioSort.newestFirst,
        ).map((track) => track.id),
        [2, 3, 1],
      );
      expect(
        AudioLibraryService.sortTracks(
          tracks,
          sort: AudioSort.oldestFirst,
        ).map((track) => track.id),
        [1, 3, 2],
      );
    });
  });

  group('LibraryCatalog favorites', () {
    test('toggles a favorite on and off', () {
      final catalog = LibraryCatalog();

      expect(catalog.toggleFavorite('12'), isTrue);
      expect(catalog.favorites, contains('12'));
      expect(catalog.toggleFavorite('12'), isFalse);
      expect(catalog.favorites, isNot(contains('12')));
    });
  });

  group('LibraryCatalog playlists', () {
    test('creates, renames, and deletes a playlist', () {
      final catalog = LibraryCatalog();

      catalog.createPlaylist('  Viagem  ');
      catalog.renamePlaylist('Viagem', 'Estrada');

      expect(catalog.playlists, contains('Estrada'));
      expect(catalog.playlists['Estrada'], isEmpty);

      catalog.deletePlaylist('Estrada');
      expect(catalog.playlists, isEmpty);
    });

    test('adds and removes tracks without duplicates', () {
      final catalog = LibraryCatalog();
      catalog.createPlaylist('Favoritas');

      expect(catalog.toggleTrack('Favoritas', '34'), isTrue);
      expect(catalog.toggleTrack('Favoritas', '34'), isFalse);
      expect(catalog.playlists['Favoritas'], isEmpty);
    });

    test('bulk add preserves input order and skips duplicates', () {
      final catalog = LibraryCatalog();
      catalog.createPlaylist('Ordem');
      catalog.addTracks('Ordem', ['8', '3']);

      final addedCount = catalog.addTracks('Ordem', ['3', '21', '8', '13']);

      expect(addedCount, 2);
      expect(catalog.playlists['Ordem'], ['8', '3', '21', '13']);
    });

    test(
      'resolves playlist tracks in saved order and skips unavailable IDs',
      () {
        final catalog = LibraryCatalog(
          playlists: {
            'Ordem': ['21', '8', '999', '3'],
          },
        );

        final tracks = catalog.tracksInPlaylist('Ordem', [
          _track(3),
          _track(21),
          _track(8),
        ]);

        expect(tracks.map((track) => track.id), [21, 8, 3]);
      },
    );

    test('rejects empty or duplicate playlist names', () {
      final catalog = LibraryCatalog();
      catalog.createPlaylist('Músicas');

      expect(() => catalog.createPlaylist('  '), throwsArgumentError);
      expect(() => catalog.createPlaylist('Músicas'), throwsArgumentError);
    });

    test('removes a deleted track from favorites and every playlist', () {
      final catalog = LibraryCatalog();
      catalog.createPlaylist('Uma');
      catalog.createPlaylist('Duas');
      catalog.toggleFavorite('7');
      catalog.toggleTrack('Uma', '7');
      catalog.toggleTrack('Duas', '7');

      catalog.removeTrack('7');

      expect(catalog.favorites, isEmpty);
      expect(
        catalog.playlists.values.every((tracks) => tracks.isEmpty),
        isTrue,
      );
    });
  });
}

AudioTrack _track(int id, {int? dateAdded}) => AudioTrack(
  id: id,
  uri: 'content://media/external/audio/media/$id',
  title: 'Faixa $id',
  artist: 'Artista',
  album: 'Álbum',
  duration: const Duration(minutes: 3),
  dateAdded: dateAdded,
);
