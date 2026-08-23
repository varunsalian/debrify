import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'stores Simkl episode progress independently for each IMDb show',
    () async {
      await StorageService.saveEpisodeSimklProgress(
        imdbId: 'tt001',
        percents: const {'1_1': 100, '1_2': 42.5},
      );
      await StorageService.saveEpisodeSimklProgress(
        imdbId: 'TT002',
        percents: const {'2_3': 67},
      );

      expect(
        await StorageService.getEpisodeSimklProgress(imdbId: 'tt001'),
        const {'1_1': 100.0, '1_2': 42.5},
      );
      expect(
        await StorageService.getEpisodeSimklProgress(imdbId: 'tt002'),
        const {'2_3': 67.0},
      );
    },
  );

  test('replacing a Simkl snapshot clears stale remote progress', () async {
    await StorageService.saveEpisodeSimklProgress(
      imdbId: 'tt001',
      percents: const {'1_1': 100, '1_2': 55},
    );
    await StorageService.saveEpisodeSimklProgress(
      imdbId: 'tt001',
      percents: const {'1_2': 25},
    );

    expect(
      await StorageService.getEpisodeSimklProgress(imdbId: 'tt001'),
      const {'1_2': 25.0},
    );

    await StorageService.saveEpisodeSimklProgress(
      imdbId: 'tt001',
      percents: const {},
    );
    expect(
      await StorageService.getEpisodeSimklProgress(imdbId: 'tt001'),
      isEmpty,
    );
  });

  test(
    'Simkl and Trakt episode snapshots do not overwrite each other',
    () async {
      await StorageService.saveEpisodeTraktProgress(
        imdbId: 'tt001',
        percents: const {'1_1': 30},
      );
      await StorageService.saveEpisodeSimklProgress(
        imdbId: 'tt001',
        percents: const {'1_1': 80},
      );

      expect(
        await StorageService.getEpisodeTraktProgress(imdbId: 'tt001'),
        const {'1_1': 30.0},
      );
      expect(
        await StorageService.getEpisodeSimklProgress(imdbId: 'tt001'),
        const {'1_1': 80.0},
      );
    },
  );

  test(
    'concurrent different-show writes are retained by every tracker store',
    () async {
      final stores =
          <
            ({
              Future<void> Function(String, Map<String, double>) save,
              Future<Map<String, double>> Function(String) read,
            })
          >[
            (
              save: (imdbId, percents) =>
                  StorageService.saveEpisodeTraktProgress(
                    imdbId: imdbId,
                    percents: percents,
                  ),
              read: (imdbId) =>
                  StorageService.getEpisodeTraktProgress(imdbId: imdbId),
            ),
            (
              save: (imdbId, percents) =>
                  StorageService.saveEpisodeSimklProgress(
                    imdbId: imdbId,
                    percents: percents,
                  ),
              read: (imdbId) =>
                  StorageService.getEpisodeSimklProgress(imdbId: imdbId),
            ),
            (
              save: (imdbId, percents) =>
                  StorageService.saveEpisodeMdblistProgress(
                    imdbId: imdbId,
                    percents: percents,
                  ),
              read: (imdbId) =>
                  StorageService.getEpisodeMdblistProgress(imdbId: imdbId),
            ),
          ];

      for (final store in stores) {
        // Ensure both concurrent saves take the asynchronous JSON decode path;
        // without a serialized read/modify/write cycle they read this same base
        // object and whichever completes last drops the other show's entry.
        await store.save('tt-seed', const {'1_1': 10});
        await Future.wait([
          store.save('tt-concurrent-a', const {'1_2': 25}),
          store.save('tt-concurrent-b', const {'2_3': 75}),
        ]);

        expect(await store.read('tt-concurrent-a'), const {'1_2': 25.0});
        expect(await store.read('tt-concurrent-b'), const {'2_3': 75.0});
      }
    },
  );

  test(
    'queued tracker writes remain bound to their initiating profile',
    () async {
      ProfileRuntime.debugReset();
      final first = ProfileScope(
        profileId: 'tracker-profile-a',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final second = ProfileScope(
        profileId: 'tracker-profile-b',
        dataGeneration: 1,
        sessionEpoch: 2,
      );
      ProfileRuntime.initializeCommitted(first);
      addTearDown(() {
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeLegacy();
      });

      final queued = <Future<void>>[
        StorageService.saveEpisodeTraktProgress(
          imdbId: 'tt-profile-a-one',
          percents: const {'1_1': 20},
        ),
        StorageService.saveEpisodeTraktProgress(
          imdbId: 'tt-profile-a-two',
          percents: const {'1_2': 40},
        ),
      ];
      ProfileRuntime.publish(second);
      await Future.wait(queued);

      expect(
        await StorageService.getEpisodeTraktProgress(
          imdbId: 'tt-profile-a-one',
        ),
        isEmpty,
      );
      final firstProfileSnapshot = await ProfileRuntime.withCapturedScope(
        first,
        () =>
            StorageService.getEpisodeTraktProgress(imdbId: 'tt-profile-a-two'),
      );
      expect(firstProfileSnapshot, const {'1_2': 40.0});
    },
  );
}
