import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/features/home/presentation/home_hero_spotlight.dart';
import 'package:debrify/models/metadata_presentation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../discover/presentation/observed_value.dart';
import '../../../theme/golden_harness.dart' show disableRuntimeFonts;
import '../fixtures/card_metadata_fixture.dart';

void main() {
  setUp(disableRuntimeFonts);
  testWidgets(
    'hero motion freezes under trailer/live cover and honors reduced motion',
    (tester) async {
      final showing = ObservedValue(false);
      final live = ObservedValue(false);
      addTearDown(showing.dispose);
      addTearDown(live.dispose);
      final data = CardMetadataFake();
      data.respond = (item) async => MetadataPresentation(item);
      Widget host({bool boxed = true, bool reduced = false}) => ProviderScope(
        overrides: [
          homeCardMetadataRepositoryProvider.overrideWith(
            (ref, epoch) => data.repository(epoch),
          ),
        ],
        child: MaterialApp(
          home: AppThemeScope(
            theme: AppThemes.legacy,
            child: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: HomeHeroSpotlight(
                item: const StremioMeta(
                  id: 'fixture',
                  type: 'movie',
                  name: 'Hero',
                ),
                background: null,
                description: 'Plot',
                isTelevision: true,
                height: 350,
                artworkCacheWidth: 1000,
                artworkCacheHeight: 600,
                boxedTrailer: boxed,
                trailerShowing: showing,
                liveTakeover: live,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      showing.value = true;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      live.value = true;
      showing.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      live.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(host(reduced: true));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(host(boxed: false));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      expect(showing.isObserved, isFalse);
      expect(live.isObserved, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
