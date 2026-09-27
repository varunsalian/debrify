import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:debrify/features/home/application/home_catalog_origin_dependencies.dart';
import 'package:debrify/features/home/application/home_local_continuation_dependencies.dart';
import 'package:debrify/features/home/data/home_catalog_origin_repository.dart';
import 'package:debrify/features/home/data/home_local_continuation_repository.dart';
import 'package:debrify/features/home/models/home_catalog_origin.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/native_series_metadata_service.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../home_progressive_pagination_test.dart' show HomeFixture;
import 'home_mdblist_continuation_screen_test.dart' show FixtureImages;

const id = 'tt97123';
final history = jsonEncode([
  {'imdbId': id, 'title': 'Saved series', 'contentType': 'series'},
]);
final playback = jsonEncode({
  'imdb:$id': {'imdbId': id, 'positionMs': 3000, 'durationMs': 10000},
});

class MissingOrigin extends HomeCatalogOriginRepository {
  MissingOrigin()
    : super(
        nativeAddon: NativeSeriesMetadataService.addon,
        isOwnerCurrent: () => true,
        scopeProgress: (item, _, _) async => item,
        readCustomOrigin: (_) async => null,
      );

  @override
  Future<HomeCatalogOrigin> prepare(
    StremioMeta item,
    StremioAddon addon, {
    required bool Function() isCurrent,
  }) async => const HomeCatalogOrigin.unavailable(
    StremioMeta(id: id, imdbId: id, name: 'Missing series', type: 'series'),
  );
}

void main() {
  late Directory images;
  setUpAll(() async {
    images = await Directory.systemTemp.createTemp(
      'unavailable-origin-images-',
    );
    final file = File('${images.path}/pixel.png');
    await file.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ),
    );
    CachedNetworkImageProvider.defaultCacheManager = FixtureImages(file);
  });
  tearDownAll(() => images.delete(recursive: true));
  for (final retire in [false, true]) {
    testWidgets(
      'real Home ${retire ? 'rejects retired confirmation' : 'removes confirmed unavailable history'}',
      (tester) async {
        var seeded = false;
        final local = HomeLocalContinuationRepository(
          readProgressSource: () async => WatchProgressSource.smart,
          readEnabled: () async => true,
          readItems: () async {
            if (!seeded) {
              seeded = true;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('continue_watching_v1', history);
              await prefs.setString('playback_state_v1', playback);
            }
            return StorageService.getContinueWatchingItems();
          },
          readAddons: () async => [],
          readEpisode: (_) async => null,
          readMovie: (_) async => null,
        );
        final home = HomeFixture(tester);
        await home.mount(
          wrap: (child) => ProviderScope(
            overrides: [
              homeLocalContinuationRepositoryProvider.overrideWithValue(local),
              homeCatalogOriginRepositoryProvider.overrideWith(
                (ref, owner) => MissingOrigin(),
              ),
            ],
            child: child,
          ),
        );
        await home.settle();
        await home.focusFast();
        await home.key(LogicalKeyboardKey.enter);
        await home.settle();
        expect(find.text('Missing series'), findsOneWidget);
        final remove = find.text('Remove from Continue Watching');
        expect(remove, findsOneWidget);
        if (retire) ProfileSessionMemory.clearAll();
        await home.drive(() async {
          await tester.tap(remove);
        });
        await home.settle();
        expect(find.byType(AlertDialog), findsNothing);
        await home.drive(() async {
          final prefs = await SharedPreferences.getInstance();
          expect(
            prefs.getString('continue_watching_v1'),
            retire ? history : '[]',
          );
          expect(
            prefs.getString('playback_state_v1'),
            retire ? playback : '{}',
          );
        });
        await home.dispose();
      },
    );
  }
}
