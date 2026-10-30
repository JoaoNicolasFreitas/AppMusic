import 'package:appmusic/models/download_job.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DownloadJob buildJob({DownloadJobStatus status = DownloadJobStatus.queued}) {
    return DownloadJob(
      id: 7,
      sourceUrl: 'https://example.com/song.mp3',
      title: 'Song',
      status: status,
      progress: 0.25,
      createdAt: 1234,
      downloadId: 42,
      bytesDownloaded: 25,
      speedBytesPerSecond: 1024,
      remainingSeconds: 75,
      totalBytes: 100,
      outputUri: 'content://media/external/audio/7',
      mediaId: 9,
      error: 'previous error',
      artist: 'Artist',
      artworkUrl: 'https://example.com/cover.jpg',
    );
  }

  test('copyWith preserves values and clears nullable fields explicitly', () {
    final original = buildJob();

    final progressed = original.copyWith(
      status: DownloadJobStatus.running,
      progress: 0.5,
      bytesDownloaded: 50,
      artist: 'New Artist',
      artworkUrl: 'https://example.com/new_cover.jpg',
    );
    expect(progressed.status, DownloadJobStatus.running);
    expect(progressed.progress, 0.5);
    expect(progressed.bytesDownloaded, 50);
    expect(progressed.outputUri, original.outputUri);
    expect(progressed.speedBytesPerSecond, 1024);
    expect(progressed.remainingSeconds, 75);
    expect(progressed.artist, 'New Artist');
    expect(progressed.artworkUrl, 'https://example.com/new_cover.jpg');

    final cleared = progressed.copyWith(
      remainingSeconds: null,
      totalBytes: null,
      outputUri: null,
      mediaId: null,
      error: null,
      artist: null,
      artworkUrl: null,
    );
    expect(cleared.remainingSeconds, isNull);
    expect(cleared.totalBytes, isNull);
    expect(cleared.outputUri, isNull);
    expect(cleared.mediaId, isNull);
    expect(cleared.error, isNull);
    expect(cleared.artist, isNull);
    expect(cleared.artworkUrl, isNull);
  });

  test('only terminal statuses are terminal', () {
    expect(buildJob(status: DownloadJobStatus.queued).isTerminal, isFalse);
    expect(buildJob(status: DownloadJobStatus.running).isTerminal, isFalse);
    expect(buildJob(status: DownloadJobStatus.paused).isTerminal, isFalse);
    expect(buildJob(status: DownloadJobStatus.completed).isTerminal, isTrue);
    expect(buildJob(status: DownloadJobStatus.failed).isTerminal, isTrue);
    expect(buildJob(status: DownloadJobStatus.cancelled).isTerminal, isTrue);
  });
}
