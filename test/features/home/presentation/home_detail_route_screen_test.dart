import 'package:debrify/features/home/application/home_detail_action_dependencies.dart';
import 'package:debrify/services/tracker_title_actions.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/features/home/application/home_detail_dependencies.dart';
import 'package:debrify/features/home/data/home_detail_readers.dart';
import 'package:debrify/features/home/presentation/home_catalog_playback_bridge.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/home/application/home_catalog_origin_dependencies.dart';
import 'package:debrify/features/home/application/home_source_editing_dependencies.dart';
import 'package:debrify/features/home/data/home_source_editing_repository.dart';
import 'package:debrify/models/series_source.dart';
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
  ReadyOrigin({this.beforePrepare})
    : super(
        nativeAddon: NativeSeriesMetadataService.addon,
        isOwnerCurrent: () => true,
        scopeProgress: (item, _, _) async => item,
        readCustomOrigin: (_) async => null,
      );
  final Future<void> Function()? beforePrepare;
  @override
  Future<HomeCatalogOrigin> prepare(
    StremioMeta item,
    StremioAddon addon, {
    required bool Function() isCurrent,
  }) async {
    await beforePrepare?.call();
    return HomeCatalogOrigin.ready(
      const StremioMeta(id: 'tt123', name: 'Fixture detail', type: 'movie'),
      addon,
    );
  }
}

class WaitingDetailSources extends Fake implements HomeSourceEditingRepository {
  final release = Completer<List<SeriesSource>?>();
  bool Function()? current;
  int providerReads = 0;
  @override
  Future<List<SeriesSource>?> load(
    String id, {
    required bool Function() isCurrent,
  }) {
    current = isCurrent;
    return release.future;
  }

  @override
  Future<HomeSourceProviders?> providers({
    required bool Function() isCurrent,
  }) async {
    providerReads++;
    return null;
  }
}

class WaitingDetailActions extends Fake implements TrackerTitleActions {
  final release = Completer<bool>();
  final calls = <(TrackingSource, TrackerTitleMutation, String, String)>[];
  bool Function()? current;

  @override
  Future<bool> mutate(
    TrackingSource tracker,
    TrackerTitleMutation mutation,
    String id,
    String type, {
    int? rating,
    String? listId,
    required bool Function() isCurrent,
  }) {
    calls.add((tracker, mutation, id, type));
    current = isCurrent;
    return release.future;
  }
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
    for (final tracker in [
      TrackingSource.trakt,
      TrackingSource.simkl,
      TrackingSource.mdblist,
    ]) {
      testWidgets(
        'real detail injects $tracker mutation and retires feedback: merged=$merged',
        (tester) async {
          final home = HomeFixture(tester);
          final actions = WaitingDetailActions();
          await home.mount(
            initialPreferences: {'merged_series_page_enabled': merged},
            wrap: (child) => ProviderScope(
              overrides: [
                homeCatalogOriginRepositoryProvider.overrideWith(
                  (ref, owner) => ReadyOrigin(),
                ),
                homeDetailActionsProvider.overrideWith((ref, owner) => actions),
              ],
              child: child,
            ),
          );
          await home.settle();
          await home.focusFast();
          await home.key(LogicalKeyboardKey.enter);
          await home.settle();
          late void Function() dispatch;
          if (merged) {
            final detail = tester.widget<MergedDetailScreen>(
              find.byType(MergedDetailScreen),
            );
            dispatch = () {
              unawaited(switch (tracker) {
                TrackingSource.trakt => detail.onTraktAction!(
                  TraktItemMenuAction.addToWatchlist,
                ),
                TrackingSource.simkl => detail.onSimklAction!(
                  SimklItemMenuAction.moveToPlanToWatch,
                ),
                _ => detail.onMdblistAction!(
                  MdblistItemMenuAction.addToWatchlist,
                ),
              });
            };
          } else {
            final detail = tester.widget<CatalogItemDetailScreen>(
              find.byType(CatalogItemDetailScreen),
            );
            dispatch = () {
              switch (tracker) {
                case TrackingSource.trakt:
                  detail.onTraktAction!(TraktItemMenuAction.addToWatchlist);
                case TrackingSource.simkl:
                  detail.onSimklAction!(SimklItemMenuAction.moveToPlanToWatch);
                default:
                  detail.onMdblistAction!(MdblistItemMenuAction.addToWatchlist);
              }
            };
          }
          await home.drive(dispatch);
          expect(actions.calls, [
            (tracker, TrackerTitleMutation.addToWatchlist, 'tt123', 'movie'),
          ]);
          expect(actions.current!(), isTrue);
          home.navigator.currentState!.pop();
          await home.settle();
          expect(actions.current!(), isFalse);
          await home.drive(() => actions.release.complete(true));
          await home.settle();
          expect(find.byType(SnackBar), findsNothing);
          await home.drive(dispatch);
          expect(actions.calls, hasLength(1));
          await home.dispose();
        },
      );
    }
    for (final retire in [false, true]) {
      testWidgets(
        'detail metadata uses injected reader and route guard: merged=$merged retired=$retire',
        (tester) async {
          final home = HomeFixture(tester);
          final release = Completer<StremioMeta?>();
          final calls = <String>[];
          final readers = HomeDetailReaders(
            isOwnerCurrent: () => true,
            trakt: (_, _, _) async => null,
            simkl: (_, _, _) async => null,
            mdblist: (_, _, _) async => null,
            recommendations: (_, _, _) async => [],
            metadata: (id, type, current) {
              calls.add('$id:$type');
              return release.future;
            },
          );
          await home.mount(
            initialPreferences: {'merged_series_page_enabled': merged},
            wrap: (child) => ProviderScope(
              overrides: [
                homeCatalogOriginRepositoryProvider.overrideWith(
                  (ref, owner) => ReadyOrigin(),
                ),
                homeDetailReadersProvider.overrideWith((ref, owner) => readers),
              ],
              child: child,
            ),
          );
          await home.settle();
          await home.focusFast();
          await home.key(LogicalKeyboardKey.enter);
          await home.settle();
          final enrich = merged
              ? tester
                    .widget<MergedDetailScreen>(find.byType(MergedDetailScreen))
                    .metaEnricher!
              : tester
                    .widget<CatalogItemDetailScreen>(
                      find.byType(CatalogItemDetailScreen),
                    )
                    .metaEnricher!;
          final pending = enrich('tt987', 'series');
          expect(calls, contains('tt987:series'));
          if (retire) {
            home.navigator.currentState!.pop();
            await home.settle();
          }
          const enriched = StremioMeta(
            id: 'tt987',
            name: 'Enriched',
            type: 'series',
          );
          await home.drive(() => release.complete(enriched));
          expect(await pending, retire ? isNull : same(enriched));
          final count = calls.length;
          if (retire) {
            expect(await enrich('tt987', 'series'), isNull);
            expect(calls, hasLength(count));
          }
          await home.dispose();
        },
      );
    }
    for (final retire in [false, true]) {
      testWidgets(
        'real source editor retires with detail: merged=$merged retired=$retire',
        (tester) async {
          final repository = WaitingDetailSources();
          final home = HomeFixture(tester);
          await home.mount(
            initialPreferences: {'merged_series_page_enabled': merged},
            wrap: (child) => ProviderScope(
              overrides: [
                homeCatalogOriginRepositoryProvider.overrideWith(
                  (ref, owner) => ReadyOrigin(),
                ),
                homeSourceEditingRepositoryProvider.overrideWith(
                  (ref, owner) => repository,
                ),
              ],
              child: child,
            ),
          );
          await home.settle();
          await home.focusFast();
          await home.key(LogicalKeyboardKey.enter);
          await home.settle();
          await home.drive(() {
            if (merged) {
              final detail = tester.widget<MergedDetailScreen>(
                find.byType(MergedDetailScreen),
              );
              unawaited(detail.onSelectSource!(detail.item));
            } else {
              tester
                  .widget<CatalogItemDetailScreen>(
                    find.byType(CatalogItemDetailScreen),
                  )
                  .onTraktAction!(TraktItemMenuAction.selectSource);
            }
          });
          expect(repository.current, isNotNull);
          expect(repository.current!(), isTrue);
          if (retire) {
            home.navigator.currentState!.pop();
            await home.settle();
          }
          expect(repository.current!(), !retire);
          await home.drive(() => repository.release.complete([]));
          await home.settle();
          expect(repository.providerReads, retire ? 0 : 1);
          await home.dispose();
        },
      );
    }

    for (final retire in [false, true]) {
      testWidgets(
        'real detail Play reaches catalog player: merged=$merged retired=$retire',
        (tester) async {
          var launches = 0;
          var preparingPlay = false;
          final release = Completer<void>(), entered = Completer<void>();
          final home = HomeFixture(tester);
          await home.mount(
            initialPreferences: {'merged_series_page_enabled': merged},
            wrap: (child) => ProviderScope(
              overrides: [
                homeCatalogOriginRepositoryProvider.overrideWith(
                  (ref, owner) => ReadyOrigin(
                    beforePrepare: () async {
                      if (preparingPlay) {
                        entered.complete();
                        await release.future;
                      }
                    },
                  ),
                ),
                homeCatalogPlaybackBridgeProvider.overrideWithValue(
                  HomeCatalogPlaybackBridge(
                    launch:
                        (
                          context, {
                          required imdbId,
                          required isMovie,
                          season,
                          episode,
                          required meta,
                          openSourcePicker,
                        }) async {
                          launches++;
                          expect(imdbId, 'tt123');
                          expect(isMovie, isTrue);
                          expect(season, isNull);
                          expect(episode, isNull);
                          expect(meta.addonId, isNotEmpty);
                          expect(meta.title, 'Fixture detail');
                          expect(openSourcePicker, isNotNull);
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
          preparingPlay = true;
          await home.drive(() {
            if (merged) {
              unawaited(
                tester
                    .widget<MergedDetailScreen>(find.byType(MergedDetailScreen))
                    .onResume(null),
              );
            } else {
              tester
                  .widget<CatalogItemDetailScreen>(
                    find.byType(CatalogItemDetailScreen),
                  )
                  .onPlay();
            }
          });
          expect(entered.isCompleted, isTrue);
          if (retire) {
            home.navigator.currentState!.pop();
            await home.settle();
          }
          await home.drive(() => release.complete());
          for (var i = 0; i < 8 && launches == 0; i++) {
            await home.settle();
          }
          expect(launches, retire ? 0 : 1);
          await home.settle();
          await home.dispose();
        },
      );
    }
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
