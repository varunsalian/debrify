import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:debrify/features/home/application/home_mdblist_continuation_dependencies.dart';
import 'package:debrify/features/home/data/home_mdblist_continuation_repository.dart';
import 'package:debrify/models/mdblist_continue_watching.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FixtureImages extends Fake implements BaseCacheManager {
  FixtureImages(this.file);
  final io.File file;
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    yield FileInfo(
      const LocalFileSystem().file(file.path),
      FileSource.Cache,
      DateTime.now().add(const Duration(hours: 1)),
      url,
    );
  }

  @override
  Future<void> removeFile(String key) async {}
}

void main() {
  late io.Directory images;
  setUpAll(() async {
    images = await io.Directory.systemTemp.createTemp('mdblist_screen_');
    final file = await io.File('${images.path}/poster.png').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ),
    );
    CachedNetworkImageProvider.defaultCacheManager = FixtureImages(file);
  });
  tearDownAll(() async {
    await images.delete(recursive: true);
  });
  for (final mode in [
    'active',
    'profile',
    'dispose',
    'search',
    'remove',
    'remove-failed',
    'remove-profile',
  ]) {
    testWidgets('MDBList Home scoped reads preserve $mode behavior', (
      tester,
    ) async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      PlatformUtil.debugSetAndroidTvCached(false);
      PlatformUtil.debugSetTvOS(false);
      SharedPreferences.setMockInitialValues({
        'stremio_addons_v1': '[]',
        'tv_home_style': 'classic',
        'home_hero_source_v1': '{"mode":"auto","ids":[]}',
      });
      StorageService.tvHomeStyleCached = 'classic';
      StremioService.instance.invalidateCache();
      addTearDown(() {
        PlatformUtil.debugSetAndroidTvCached(null);
        PlatformUtil.debugSetTvOS(null);
        ProfileRuntime.debugReset();
      });
      MdblistResult<MdblistContinueWatchingSnapshot> rows() =>
          MdblistResult.partial(
            MdblistContinueWatchingSnapshot(
              movies: [
                MdblistContinueWatchingItem(
                  selection: const AdvancedSearchSelection(
                    imdbId: 'tt1234567',
                    isSeries: false,
                    title: 'MDBList fixture',
                    mdblistProgressPercent: 50,
                    mdblistSource: true,
                  ),
                  paused: true,
                  clearTarget: const MdblistScrobbleTarget.movie(
                    MdblistMediaIds(imdb: 'tt1234567'),
                  ),
                ),
              ],
            ),
          );
      final pending =
          Completer<MdblistResult<MdblistContinueWatchingSnapshot>>();
      final clearResult = Completer<bool>();
      final removals = <MdblistContinueWatchingItem>[];
      var reads = 0;
      var failed = false;
      var disconnected = false;
      final client = MockClient((_) async => http.Response('[]', 200));
      Future<void> drive(FutureOr<void> Function() action) => tester.runAsync(
        () => http.runWithClient(() async {
          await action();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }, () => client),
      );
      Future<void> pump() => http.runWithClient(
        () => tester.pump(const Duration(milliseconds: 100)),
        () => client,
      );
      await drive(
        () => tester.pumpWidget(
          ProviderScope(
            overrides: [
              homeMdblistContinuationRepositoryProvider.overrideWithValue(
                HomeMdblistContinuationRepository(
                  clear: (item) {
                    removals.add(item);
                    return clearResult.future;
                  },
                  invalidate: () {},
                  synchronizeInvalidations: () async => true,
                  fetch: ({required force}) {
                    reads++;
                    if (reads == 1) return pending.future;
                    return Future.value(
                      failed
                          ? const MdblistResult.failure(
                              MdblistResultKind.transientFailure,
                            )
                          : disconnected
                          ? const MdblistResult.success(
                              MdblistContinueWatchingSnapshot(),
                            )
                          : rows(),
                    );
                  },
                ),
              ),
            ],
            child: MaterialApp(
              home: SearchScreen(
                isTelevision: true,
                searchMode: mode == 'search',
                discoverMode: mode == 'discover',
              ),
            ),
          ),
        ),
      );
      expect(reads, mode == 'search' ? 0 : 1);
      if (mode == 'dispose') await tester.pumpWidget(const SizedBox());
      if (mode == 'profile') {
        ProfileRuntime.promoteLegacyToCommitted(
          ProfileScope(
            profileId: 'incoming',
            dataGeneration: 1,
            sessionEpoch: 1,
          ),
        );
      }
      await drive(() => pending.complete(rows()));
      await pump();
      Iterable<FocusNode> nodes() => find
          .text('MDBList fixture')
          .evaluate()
          .map((e) => Focus.maybeOf(e))
          .whereType<FocusNode>();
      if (mode.startsWith('remove')) {
        final node = nodes().single;
        node.requestFocus();
        await pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await drive(() {});
        await pump();
        expect(find.text('Remove from Continue Watching'), findsOneWidget);
        await drive(
          () => tester.tap(find.text('Remove from Continue Watching')),
        );
        await pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(removals.single.selection.imdbId, 'tt1234567');
        expect(removals.single.clearTarget!.ids.imdb, 'tt1234567');
        expect(reads, 1);
        if (mode == 'remove-profile') {
          ProfileRuntime.promoteLegacyToCommitted(
            ProfileScope(
              profileId: 'incoming',
              dataGeneration: 1,
              sessionEpoch: 1,
            ),
          );
        }
        disconnected = mode == 'remove';
        await drive(() => clearResult.complete(mode != 'remove-failed'));
        await pump();
        expect(reads, mode == 'remove' ? 2 : 1);
        expect(
          find.text('Removed from MDBList Continue Watching'),
          mode == 'remove' ? findsOneWidget : findsNothing,
        );
        if (mode == 'remove') {
          expect(nodes(), isEmpty);
        } else if (mode == 'remove-failed') {
          expect(nodes().single, same(node));
          expect(node.hasFocus, isTrue);
        }
      } else if (mode == 'active') {
        final node = nodes().single;
        node.requestFocus();
        await pump();
        failed = true;
        await drive(MainPageBridge.notifyIntegrationChanged);
        await pump();
        expect(reads, 2);
        expect(nodes().single, same(node));
        expect(node.hasFocus, isTrue);
        failed = false;
        disconnected = true;
        await drive(MainPageBridge.notifyIntegrationChanged);
        await pump();
        expect(reads, 3);
        expect(nodes(), isEmpty);
      } else {
        expect(nodes(), isEmpty);
        expect(reads, mode == 'search' ? 0 : 1);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
