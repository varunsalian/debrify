import 'dart:async';
import 'package:debrify/features/home/application/home_trailer_preferences_dependencies.dart';
import 'package:debrify/features/home/data/home_trailer_preferences_repository.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;

void main() {
  for (final television in [true, false]) {
    testWidgets(
      'Home uses current audio surface and rejects late startup: TV=$television',
      (tester) async {
        final startup = Completer<bool>();
        var reads = 0;
        final audioSurfaces = <bool>[];
        final volumeSurfaces = <bool>[];
        final repo = HomeTrailerPreferencesRepository(
          readEnabled: () =>
              ++reads == 1 ? startup.future : Future.value(false),
          readAudioEnabled: (home) async {
            audioSurfaces.add(home);
            return true;
          },
          readVolume: (home) async {
            volumeSurfaces.add(home);
            return home ? 36 : 68;
          },
        );
        final home = HomeFixture(
          tester,
          style: 'spotlight',
          television: television,
        );
        home.slow.complete(page('Slow'));
        await home.mount(
          wrap: (child) => ProviderScope(
            overrides: [
              homeTrailerPreferencesRepositoryProvider.overrideWithValue(repo),
            ],
            child: child,
          ),
        );
        SpotlightBoard board() =>
            tester.widget<SpotlightBoard>(find.byType(SpotlightBoard));
        expect(board().trailersEnabled, isFalse);
        expect(board().cardTrailerVolume, 0);
        await home.drive(MainPageBridge.notifyHomeSettingsChanged);
        await home.settle();
        expect(board().trailersEnabled, isFalse);
        expect(board().cardTrailerVolume, television ? 36 : 68);
        await home.drive(() => startup.complete(true));
        await home.settle();
        expect(board().trailersEnabled, isFalse);
        expect(board().cardTrailerVolume, television ? 36 : 68);
        expect(audioSurfaces, [television, television]);
        expect(volumeSurfaces, [television, television]);
        await home.dispose();
      },
    );
  }
}
