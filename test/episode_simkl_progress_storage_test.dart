import 'package:debrify/services/storage_service.dart';
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
}
