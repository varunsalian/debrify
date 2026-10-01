import 'dart:async';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'dart:convert';
import 'dart:io' as io;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/home/application/home_continuation_providers.dart';
import 'package:debrify/features/home/data/home_episode_artwork_repository.dart';
import 'package:debrify/models/simkl_continue_watching_item.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;
import 'home_mdblist_continuation_screen_test.dart' show FixtureImages;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late io.Directory images;
  setUpAll(() async {
    images = await io.Directory.systemTemp.createTemp('episode_art_screen_');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => images.path,
        );
    final file = await io.File('${images.path}/poster.png').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ),
    );
    CachedNetworkImageProvider.defaultCacheManager = FixtureImages(file);
    for (final name in ['current', 'refreshed', 'old']) {
      await DebrifyImageCache.manager.putFile(
        'https://art.invalid/$name.png',
        await file.readAsBytes(),
        fileExtension: 'png',
      );
    }
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await images.delete(recursive: true);
  });
  testWidgets(
    'Home cards accept the current episode and reload stills on metadata changes',
    (tester) async {
      final home = HomeFixture(tester, style: 'spotlight');
      Future<void> settle() async {
        for (var frame = 0; frame < 4; frame++) {
          await home.drive(
            () => tester.pump(const Duration(milliseconds: 150)),
          );
        }
      }

      final responses = <Completer<String?>>[];
      final episodes = <int>[];
      var episode = 1;
      await home.mount(
        wrap: (child) => ProviderScope(
          overrides: [
            homeSimklContinuationReaderProvider.overrideWithValue(
              () async => (
                movies: <SimklContinueWatchingItem>[],
                shows: [
                  SimklContinueWatchingItem(
                    meta: StremioMeta(
                      id: 'tt1234567',
                      imdbId: 'tt1234567',
                      type: 'series',
                      name: 'Episode fixture',
                    ),
                    progress: 25,
                    season: 1,
                    episode: episode,
                    pausedAtMs: null,
                    isMovie: false,
                  ),
                ],
              ),
            ),
            homeEpisodeArtworkRepositoryProvider.overrideWith(
              (ref, session) => HomeEpisodeArtworkRepository(({
                required imdbId,
                required season,
                required episode,
              }) {
                expect(imdbId, 'tt1234567');
                expect(season, 1);
                episodes.add(episode);
                final response = Completer<String?>();
                responses.add(response);
                return response.future;
              }),
            ),
          ],
          child: child,
        ),
      );
      await home.drive(() => home.slow.complete(page('Slow')));
      await settle();
      SpotlightCard card() => tester
          .widget<SpotlightBoard>(find.byType(SpotlightBoard))
          .sections
          .expand((shelf) => shelf.items)
          .singleWhere((item) => item.title == 'Episode fixture');
      expect(episodes, [1]);
      expect(card().episodeArtwork, isFalse);
      episode = 2;
      await home.drive(MainPageBridge.notifyIntegrationChanged);
      await settle();
      expect(episodes, [1, 2]);
      await home.drive(
        () => responses[1].complete('https://art.invalid/current.png'),
      );
      await settle();
      expect(card().image, 'https://art.invalid/current.png');
      expect(card().episodeArtwork, isTrue);
      await home.drive(() => MetadataPreferencesService.revision.value++);
      await settle();
      expect(episodes, [1, 2, 2]);
      expect(card().episodeArtwork, isFalse);
      await home.drive(
        () => responses[2].complete('https://art.invalid/refreshed.png'),
      );
      await settle();
      expect(card().image, 'https://art.invalid/refreshed.png');
      await home.drive(
        () => responses[0].complete('https://art.invalid/old.png'),
      );
      await settle();
      expect(card().image, 'https://art.invalid/refreshed.png');
      expect(tester.takeException(), isNull);
      await home.dispose();
      await home.drive(() => DebrifyImageCache.manager.dispose());
    },
  );
}
