import 'package:debrify/features/home/application/home_hero_trailer_dependencies.dart';
import 'package:debrify/features/home/application/home_trailer_preferences_dependencies.dart';
import 'package:debrify/features/home/data/home_hero_trailer_repository.dart';
import 'package:debrify/features/home/data/home_trailer_preferences_repository.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/metadata_details_service.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;
import '../../theme/golden_harness.dart' show disableRuntimeFonts;

void main() {
  setUp(disableRuntimeFonts);
  testWidgets(
    'Spotlight content launch suppresses same-title dwell until a new title',
    (tester) async {
      addTearDown(MainPageBridge.notifyContentPlaybackStopped);
      var resolves = 0;
      final repo = HomeHeroTrailerRepository(
        readPreferences: (current) async =>
            current() ? MetadataPreferences() : null,
        selectTrailers: (_, _, _) async => [
          const MetadataTrailer(
            key: 'yt',
            title: '',
            language: '',
            type: '',
            official: false,
          ),
        ],
        fetchDetails: (_, _) async => null,
        resolveYoutube: (_) async {
          resolves++;
          return null;
        },
        resolveImdb: (_) async => null,
      );
      final home = HomeFixture(
        tester,
        style: 'spotlight',
        television: false,
        fastCount: 2,
      );
      home.slow.complete(page('Slow'));
      await home.mount(
        wrap: (child) => ProviderScope(
          overrides: [
            homeHeroTrailerRepositoryProvider.overrideWithValue(repo),
            homeTrailerPreferencesRepositoryProvider.overrideWithValue(
              HomeTrailerPreferencesRepository(
                readEnabled: () async => true,
                readAudioEnabled: (_) async => false,
                readVolume: (_) async => 0,
              ),
            ),
          ],
          child: child,
        ),
      );
      await home.settle();
      SpotlightBoard board() =>
          tester.widget<SpotlightBoard>(find.byType(SpotlightBoard));
      final first = board().hero.first;
      final next = board().hero[1];
      Future<void> dwell(bool second) async {
        board().onDwell!(second ? next : first);
        await home.pump(Duration.zero);
        await home.settle();
      }

      await dwell(false);
      final before = resolves;
      expect(before, greaterThan(0));
      MainPageBridge.notifyPlayerLaunching(isTrailer: true);
      await dwell(false);
      expect(resolves, before + 1);
      MainPageBridge.notifyPlayerLaunching();
      await dwell(false);
      expect(resolves, before + 1);
      await dwell(true);
      expect(resolves, before + 2);
      await home.dispose();
    },
  );
}
