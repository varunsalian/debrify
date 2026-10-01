import 'dart:async';
import 'package:debrify/features/home/application/home_hero_providers.dart';
import 'package:debrify/features/home/data/home_hero_trailer_repository.dart';
import 'package:debrify/features/home/data/home_trailer_preferences_repository.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/services/metadata_details_service.dart';
import 'package:debrify/services/app_route_observer.dart';
import 'package:debrify/services/youtube_service.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;
import '../../theme/golden_harness.dart' show disableRuntimeFonts;

void main() {
  setUp(disableRuntimeFonts);
  for (final covered in [false, true]) {
    testWidgets(
      'Home rejects late injected trailer results (covered=$covered)',
      (tester) async {
        final stream = Completer<YoutubeResolvedStreams?>();
        var resolves = 0;
        final repo = HomeHeroTrailerRepository(
          readPreferences: (current) async =>
              current() ? MetadataPreferences() : null,
          selectTrailers: (_, _, _) async => [
            const MetadataTrailer(
              key: 'fixture',
              title: 'Trailer',
              language: '',
              type: 'Trailer',
              official: true,
            ),
          ],
          fetchDetails: (_, _) async =>
              throw StateError('selected trailer needs no details'),
          resolveYoutube: (_) {
            resolves++;
            return stream.future;
          },
          resolveImdb: (_) async =>
              throw StateError('playable YouTube needs no backup'),
        );
        final home = HomeFixture(tester, style: 'canvas');
        home.slow.complete(page('Slow'));
        await home.mount(
          observers: [appRouteObserver],
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
        await home.focusFast();
        await home.pump(const Duration(seconds: 3));
        await home.settle();
        expect(resolves, 1);
        expect(find.byType(HeroTrailerBackdrop), findsNothing);
        if (covered) {
          await home.cover();
        } else {
          await home.dispose();
        }
        await home.drive(
          () => stream.complete(
            const YoutubeResolvedStreams(
              playUrl: 'https://fixture.invalid/video',
            ),
          ),
        );
        await home.settle();
        expect(
          find.byType(HeroTrailerBackdrop, skipOffstage: false),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        if (covered) await home.dispose();
      },
    );
  }
}
