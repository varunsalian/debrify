import 'dart:convert';

import 'package:debrify/services/playback_recovery_intent.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _historyKey = 'remote_tv_playback_recovery_deletions_v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfilePreferenceBudget.debugReset();
    PlaybackRecoveryIntent.debugReset();
    PlaybackRecoveryIntent.debugSupportedOverride = true;
  });
  tearDown(() {
    PlaybackRecoveryIntent.debugReset();
    ProfilePreferenceBudget.debugReset();
    ProfileRuntime.debugReset();
    SharedPreferences.setMockInitialValues({});
  });

  for (final throwing in [false, true]) {
    test(
      'history ${throwing ? 'exception' : 'rejection'} does not fail unwatch',
      () async {
        final store = _FailingHistoryStore(throwing: throwing, failures: 1);
        SharedPreferencesStorePlatform.instance = store;
        await StorageService.markMovieAsFinished('tt1234');
        final before = DateTime.now().millisecondsSinceEpoch - 1000;
        await StorageService.unmarkMovieAsFinished('tt1234');
        expect(await StorageService.isMovieFinished('tt1234'), isFalse);
        expect(store.historyWrites, 2);
        // Lose the isolate-only fallback; the small cutoff must be durable.
        PlaybackRecoveryIntent.debugReset();
        PlaybackRecoveryIntent.debugSupportedOverride = true;
        await (await SharedPreferences.getInstance()).reload();
        expect(
          await PlaybackRecoveryIntent.hasNewer(['any-old-item'], before),
          isTrue,
        );
      },
    );
  }

  test('unwatch still works when both history writes fail', () async {
    SharedPreferencesStorePlatform.instance = _FailingHistoryStore(
      throwing: true,
      failures: 2,
    );
    await StorageService.markMovieAsFinished('tt1234');
    final before = DateTime.now().millisecondsSinceEpoch - 1000;
    await StorageService.unmarkMovieAsFinished('tt1234');
    expect(await StorageService.isMovieFinished('tt1234'), isFalse);
    await (await SharedPreferences.getInstance()).reload();
    expect(
      (await SharedPreferences.getInstance()).getString(_historyKey),
      isNull,
    );
    expect(
      await PlaybackRecoveryIntent.hasNewer(['any-old-item'], before),
      isTrue,
    );
  });

  test(
    'a fallback fence cannot leak to another profile or generation',
    () async {
      ProfileRuntime.debugReset();
      final scope = ProfileScope(
        profileId: 'adult',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      SharedPreferencesStorePlatform.instance = _FailingHistoryStore(
        throwing: true,
        failures: 2,
      );
      final before = DateTime.now().millisecondsSinceEpoch - 1000;
      await PlaybackRecoveryIntent.record(['item']);
      expect(await PlaybackRecoveryIntent.hasNewer(['item'], before), isTrue);
      for (final other in [
        ProfileScope(profileId: 'kids', dataGeneration: 1, sessionEpoch: 2),
        ProfileScope(profileId: 'adult', dataGeneration: 2, sessionEpoch: 3),
      ]) {
        ProfileRuntime.publish(other);
        expect(
          await PlaybackRecoveryIntent.hasNewer(['item'], before),
          isFalse,
        );
      }
    },
  );

  test(
    'corrupt history is replaced with a cutoff while progress clears',
    () async {
      SharedPreferences.setMockInitialValues({_historyKey: '{broken'});
      await StorageService.saveVideoPlaybackState(
        videoTitle: 'Movie',
        videoUrl: 'https://example.invalid/video',
        positionMs: 1000,
        durationMs: 100000,
        imdbId: 'tt1234',
      );
      final before = DateTime.now().millisecondsSinceEpoch - 1000;
      await StorageService.clearPlaybackStateByImdbId('tt1234');
      expect(
        await StorageService.getVideoPlaybackState(videoTitle: 'Movie'),
        isNull,
      );
      PlaybackRecoveryIntent.debugReset();
      PlaybackRecoveryIntent.debugSupportedOverride = true;
      expect(
        await PlaybackRecoveryIntent.hasNewer(['any-old-item'], before),
        isTrue,
      );
    },
  );

  test('a rejected large history write falls back to a small cutoff', () async {
    // Fault injection: the real budget is tvOS-only, whereas history is Android-only.
    // Force both to exercise the false-return branch in the preference facade.
    final playback = jsonEncode({
      'series_example': {
        'type': 'series',
        'title': 'Example',
        'imdbId': 'tt1234',
        'seasons': {
          '1': {
            for (var episode = 1; episode <= 200; episode++)
              '$episode': {'positionMs': 10, 'durationMs': 100},
          },
        },
      },
    });
    final base =
        ProfilePreferenceBudget.entryFootprint('playback_state_v1', playback) +
        ProfilePreferenceBudget.entryFootprint('padding', '');
    SharedPreferences.setMockInitialValues({
      'playback_state_v1': playback,
      'padding': 'x' * (ProfilePreferenceBudget.limitBytes - base - 10),
    });
    ProfilePreferenceBudget.debugEnforcedOverride = true;
    await StorageService.clearPlaylistProgress(title: 'Example');
    expect(
      await StorageService.getSeriesPlaybackState(
        seriesTitle: 'Example',
        season: 1,
        episode: 1,
      ),
      isNull,
    );
    final history =
        jsonDecode(
              (await SharedPreferences.getInstance()).getString(_historyKey)!,
            )
            as Map;
    expect(history.keys, ['*']);
  });

  for (final corrupt in [
    '{broken',
    '[]',
    'null',
    '{"item":"bad"}',
    '{"item":-1}',
  ]) {
    test('corrupt history read fails closed and repairs $corrupt', () async {
      SharedPreferences.setMockInitialValues({_historyKey: corrupt});
      final before = DateTime.now().millisecondsSinceEpoch - 1000;
      expect(await PlaybackRecoveryIntent.hasNewer(['item'], before), isTrue);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final repaired = jsonDecode(prefs.getString(_historyKey)!) as Map;
      expect(repaired.keys, ['*']);
      final cutoff = repaired['*'] as int;
      PlaybackRecoveryIntent.debugReset();
      PlaybackRecoveryIntent.debugSupportedOverride = true;
      expect(
        await PlaybackRecoveryIntent.hasNewer(['unrelated'], before),
        isTrue,
      );
      // Only the unknowable old history is fenced, not all future playback.
      expect(
        await PlaybackRecoveryIntent.hasNewer(['item'], cutoff + 1),
        isFalse,
      );
    });
  }

  for (final throwing in [false, true]) {
    test(
      'failed corrupt-history repair still consumes old replay ($throwing)',
      () async {
        final store = _FailingHistoryStore(throwing: throwing, failures: 2);
        SharedPreferencesStorePlatform.instance = store;
        final prefs = await SharedPreferences.getInstance();
        // Seed the corrupt value without spending the injected repair failures.
        await store.seedCorruptHistory();
        await prefs.reload();
        final before = DateTime.now().millisecondsSinceEpoch - 1000;
        expect(await PlaybackRecoveryIntent.hasNewer(['item'], before), isTrue);
        expect(await PlaybackRecoveryIntent.hasNewer(['item'], before), isTrue);
        expect(
          store.historyWrites,
          1,
          reason: 'the in-memory cutoff avoids repeated repair attempts',
        );
      },
    );
  }
}

class _FailingHistoryStore extends InMemorySharedPreferencesStore {
  _FailingHistoryStore({required this.throwing, required this.failures})
    : super.empty();
  final bool throwing;
  final int failures;
  int historyWrites = 0;

  Future<void> seedCorruptHistory() async {
    await super.setValue('String', 'flutter.$_historyKey', '{broken');
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith(_historyKey) && ++historyWrites <= failures) {
      if (throwing) throw StateError('history store unavailable');
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}
