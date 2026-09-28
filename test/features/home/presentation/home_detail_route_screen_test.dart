import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/home/application/home_catalog_origin_dependencies.dart';
import 'package:debrify/features/home/application/home_local_history_removal_dependencies.dart';
import 'package:debrify/features/home/data/home_catalog_origin_repository.dart';
import 'package:debrify/features/home/models/home_catalog_origin.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/screens/episodes_screen.dart'
    show kCatalogDetailRouteName;
import 'package:debrify/services/local_history_removal.dart';
import 'package:debrify/services/native_series_metadata_service.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../home_progressive_pagination_test.dart' show HomeFixture;
import '../home_mdblist_continuation_screen_test.dart' show FixtureImages;

class ReadyOrigin extends HomeCatalogOriginRepository {
  ReadyOrigin()
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
  }) async => HomeCatalogOrigin.ready(
    const StremioMeta(id: 'tt123', name: 'Fixture detail', type: 'movie'),
    addon,
  );
}

void main() {
  late Directory images;
  setUpAll(() async {
    images = await Directory.systemTemp.createTemp('detail-route-images-');
    final file = File('${images.path}/pixel.png');
    await file.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ),
    );
    CachedNetworkImageProvider.defaultCacheManager = FixtureImages(file);
  });
  tearDownAll(() => images.delete(recursive: true));
  for (final merged in [false, true]) {
    for (final replace in [false, true]) {
      testWidgets(
        'real detail delayed removal retains newer route: merged=$merged replaced=$replace',
        (tester) async {
          final release = Completer<void>();
          final entered = Completer<void>();
          final home = HomeFixture(tester);
          await home.mount(
            initialPreferences: {'merged_series_page_enabled': merged},
            wrap: (child) => ProviderScope(
              overrides: [
                homeCatalogOriginRepositoryProvider.overrideWith(
                  (ref, owner) => ReadyOrigin(),
                ),
                homeLocalHistoryRemovalProvider.overrideWith(
                  (ref, owner) => LocalHistoryRemoval(
                    isOwnerCurrent: () => true,
                    write: (id) async {
                      expect(id, 'tt123');
                      entered.complete();
                      await release.future;
                    },
                  ),
                ),
              ],
              child: child,
            ),
          );
          await home.settle();
          await home.focusFast();
          await home.key(LogicalKeyboardKey.enter);
          await home.settle();
          void Function(TraktItemMenuAction)? dispatch;
          if (merged) {
            dispatch = tester
                .widget<MergedDetailScreen>(find.byType(MergedDetailScreen))
                .onTraktAction;
          } else {
            dispatch = tester
                .widget<CatalogItemDetailScreen>(
                  find.byType(CatalogItemDetailScreen),
                )
                .onTraktAction;
          }
          expect(dispatch, isNotNull);
          dispatch!(TraktItemMenuAction.removeFromPlayback);
          await entered.future.timeout(const Duration(seconds: 3));
          final nav = home.navigator.currentState!;
          if (replace) {
            nav.pop();
            await home.settle();
          }
          final newer = nav.push<void>(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: kCatalogDetailRouteName),
              builder: (_) => const Scaffold(body: Text('Newer detail')),
            ),
          );
          await home.settle();
          release.complete();
          await LocalHistoryRemoval.drain();
          await home.settle();
          expect(find.text('Newer detail'), findsOneWidget);
          nav.pop();
          await newer;
          await home.settle();
          if (!replace) {
            expect(
              find.byType(
                merged ? MergedDetailScreen : CatalogItemDetailScreen,
              ),
              findsOneWidget,
            );
            nav.pop();
            await home.settle();
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
