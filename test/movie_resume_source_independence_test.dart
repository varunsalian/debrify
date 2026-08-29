import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/local_playback_resume_resolver.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A movie's resume record is keyed by release filename (or by debrid file id),
/// so relaunching the same film through a different source — Quick Play
/// auto-picking another torrent after an unpin, a startup failover landing on a
/// later candidate — used to miss it and restart from zero on Android TV.
/// `readMovieResumeState` recovers it via the IMDb id, matching the Flutter
/// player's own cascade.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  PlaylistEntry entry(String title, {String? provider, int? torboxFileId}) =>
      PlaylistEntry(
        url: 'https://example.test/${title.hashCode}.mkv',
        title: title,
        provider: provider,
        torboxTorrentId: torboxFileId == null ? null : 42,
        torboxFileId: torboxFileId,
      );

  Future<void> saveFor(
    PlaylistEntry e, {
    required String imdbId,
    required int positionMs,
    double speed = 1,
    String aspect = 'contain',
  }) {
    return StorageService.saveVideoPlaybackState(
      videoTitle: VideoPlayerLauncher.resumeIdForEntry(e),
      videoUrl: e.url,
      positionMs: positionMs,
      durationMs: 7200000,
      speed: speed,
      aspect: aspect,
      imdbId: imdbId,
    );
  }

  test(
    'a different release of the same movie resumes where the last one stopped',
    () async {
      final watched = entry('Some.Movie.2019.1080p.BluRay.x264-GROUP');
      await saveFor(watched, imdbId: 'tt1234567', positionMs: 3600000);

      final replacement = entry(
        'Some Movie 2019 2160p WEB-DL DDP5.1 HDR-OTHER',
      );
      final state = await VideoPlayerLauncher.readMovieResumeState(
        entry: replacement,
        imdbId: 'tt1234567',
      );

      expect(state?['positionMs'], 3600000);
    },
  );

  test('the source-specific record still wins over the IMDb scan', () async {
    final current = entry('Some.Movie.2019.1080p.BluRay.x264-GROUP');
    await saveFor(current, imdbId: 'tt1234567', positionMs: 600000);
    // A newer write under a different release must not shadow this entry's own.
    await saveFor(
      entry('Some Movie 2019 2160p WEB-DL-OTHER'),
      imdbId: 'tt1234567',
      positionMs: 5400000,
    );

    final state = await VideoPlayerLauncher.readMovieResumeState(
      entry: current,
      imdbId: 'tt1234567',
    );

    expect(state?['positionMs'], 600000);
  });

  test(
    'catalog playback uses the newest IMDb record over an older exact source',
    () async {
      final current = entry('Some.Movie.2019.1080p.BluRay.x264-GROUP');
      await saveFor(
        current,
        imdbId: 'tt1234567',
        positionMs: 600000,
        speed: 1.25,
        aspect: 'cover',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await saveFor(
        entry('Some Movie 2019 2160p WEB-DL-OTHER'),
        imdbId: 'tt1234567',
        positionMs: 5400000,
        speed: 2,
        aspect: 'contain',
      );

      final state = await VideoPlayerLauncher.readMovieResumeState(
        entry: current,
        imdbId: 'tt1234567',
        policy: PlaybackResumePolicy.catalogCanonical,
      );

      expect(state?['positionMs'], 5400000);
      // The behavior change is deliberately position-only: returning to an
      // exact source retains that source's presentation preferences.
      expect(state?['speed'], 1.25);
      expect(state?['aspect'], 'cover');
    },
  );

  test('catalog playback falls back to a pre-IMDb exact record', () async {
    final current = entry('Legacy.Movie.2018.1080p');
    await StorageService.saveVideoPlaybackState(
      videoTitle: VideoPlayerLauncher.resumeIdForEntry(current),
      videoUrl: current.url,
      positionMs: 1200000,
      durationMs: 6000000,
    );

    final state = await VideoPlayerLauncher.readMovieResumeState(
      entry: current,
      imdbId: 'tt7654321',
      policy: PlaybackResumePolicy.catalogCanonical,
    );

    expect(state?['positionMs'], 1200000);
  });

  test(
    'catalog playback rejects an exact key tagged to another IMDb id',
    () async {
      final current = entry('Colliding.Release.Name');
      await saveFor(current, imdbId: 'tt0000001', positionMs: 1200000);

      final state = await VideoPlayerLauncher.readMovieResumeState(
        entry: current,
        imdbId: 'tt0000002',
        policy: PlaybackResumePolicy.catalogCanonical,
      );

      expect(state, isNull);
    },
  );

  test('a finished movie is not resurrected through the fallback', () async {
    await saveFor(
      entry('Some.Movie.2019.1080p.BluRay.x264-GROUP'),
      imdbId: 'tt1234567',
      positionMs: 7000000,
    );
    await StorageService.markMovieAsFinished('tt1234567');

    final state = await VideoPlayerLauncher.readMovieResumeState(
      entry: entry('Some Movie 2019 2160p WEB-DL-OTHER'),
      imdbId: 'tt1234567',
      policy: PlaybackResumePolicy.catalogCanonical,
    );

    expect(state, isNull);
  });

  test('a blank IMDb id never matches an unrelated record', () async {
    await StorageService.saveVideoPlaybackState(
      videoTitle: VideoPlayerLauncher.resumeIdForEntry(entry('Unrelated.File')),
      videoUrl: 'https://example.test/unrelated.mkv',
      positionMs: 900000,
      durationMs: 5400000,
      imdbId: '',
    );

    expect(
      await VideoPlayerLauncher.readMovieResumeState(
        entry: entry('Some Movie 2019 2160p WEB-DL-OTHER'),
        imdbId: '',
      ),
      isNull,
    );
    expect(
      await VideoPlayerLauncher.readMovieResumeState(
        entry: entry('Some Movie 2019 2160p WEB-DL-OTHER'),
        imdbId: null,
      ),
      isNull,
    );
    expect(await StorageService.getVideoPlaybackStateByImdbId(''), isNull);
  });

  test('debrid file-id keys recover across providers too', () async {
    final onTorbox = entry(
      'Some.Movie.2019',
      provider: 'torbox',
      torboxFileId: 7,
    );
    await saveFor(onTorbox, imdbId: 'tt1234567', positionMs: 2400000);

    // Same film re-resolved through a plain link: a wholly different key space.
    final state = await VideoPlayerLauncher.readMovieResumeState(
      entry: entry('Some.Movie.2019.WEBRip-OTHER'),
      imdbId: 'tt1234567',
    );

    expect(state?['positionMs'], 2400000);
  });

  test('a malformed imdbId field does not throw out of the scan', () async {
    SharedPreferences.setMockInitialValues({
      'playback_state_v1':
          '{"video_broken":{"type":"video","imdbId":1234,"positionMs":10,'
          '"durationMs":20,"updatedAt":99},'
          '"video_ok":{"type":"video","imdbId":"tt1234567","positionMs":3600000,'
          '"durationMs":7200000,"updatedAt":1}}',
    });

    expect(
      (await StorageService.getVideoPlaybackStateByImdbId(
        'tt1234567',
      ))?['positionMs'],
      3600000,
    );
  });

  test('an unknown movie still resolves to nothing', () async {
    expect(
      await VideoPlayerLauncher.readMovieResumeState(
        entry: entry('Never.Watched.2021'),
        imdbId: 'tt9999999',
      ),
      isNull,
    );
  });
}
