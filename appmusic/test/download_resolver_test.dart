import 'package:appmusic/services/download_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadResolver', () {
    final resolver = DownloadResolver();

    test('extractVideoId identifies video ID from multiple formats', () {
      expect(resolver.extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
      expect(resolver.extractVideoId('https://youtu.be/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
      expect(resolver.extractVideoId('https://youtu.be/dQw4w9WgXcQ?si=abcdef'), 'dQw4w9WgXcQ');
      expect(resolver.extractVideoId('https://m.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
      expect(resolver.extractVideoId('https://www.youtube.com/shorts/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
      expect(resolver.extractVideoId('https://www.youtube.com/embed/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
      expect(resolver.extractVideoId('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
      expect(resolver.extractVideoId('1462VchM2IU'), '1462VchM2IU');
      expect(resolver.extractVideoId('https://example.com/audio.mp3'), isNull);
      expect(resolver.extractVideoId('not-a-valid-id'), isNull);
    });

    test('isYouTubeSource detects YouTube sources accurately', () {
      expect(resolver.isYouTubeSource('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
      expect(resolver.isYouTubeSource('https://youtu.be/dQw4w9WgXcQ'), isTrue);
      expect(resolver.isYouTubeSource('dQw4w9WgXcQ'), isTrue);
      expect(resolver.isYouTubeSource('https://example.com/audio.mp3'), isFalse);
    });

    test('resolve handles direct HTTP links properly', () async {
      final preview = await resolver.resolve('https://example.com/musicas/rock_song.mp3?download=1');
      expect(preview.isYouTube, isFalse);
      expect(preview.title, 'rock_song');
      expect(preview.options.length, 1);
      expect(preview.options.first.extension, 'mp3');
      expect(preview.options.first.downloadUrl, 'https://example.com/musicas/rock_song.mp3?download=1');
    });

    test('resolve throws ArgumentError on invalid inputs', () async {
      expect(
        () => resolver.resolve('not-a-valid-url-or-id'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
