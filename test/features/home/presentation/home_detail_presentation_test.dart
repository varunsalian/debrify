import 'package:debrify/features/home/presentation/home_detail_menus.dart';
import 'package:flutter/material.dart';
import 'package:debrify/features/home/presentation/home_detail_presentation.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final merged in [false, true]) {
    for (final type in ['movie', 'series', 'tv']) {
      test(
        'detail composition preserves $type contracts with merged=$merged',
        () async {
          final addon = StremioAddon(
            id: 'origin',
            name: 'Origin',
            manifestUrl: 'https://fixture.invalid/manifest.json',
            baseUrl: 'https://fixture.invalid',
          );
          final item = StremioMeta(id: 'tt123', type: type, name: 'Fixture');
          final plays = <Map<String, Object?>>[];
          final calls = <String>[];
          var boundReads = 0;
          const selection = AdvancedSearchSelection(
            imdbId: 'tt123',
            title: 'Fixture',
            isSeries: true,
            season: 5,
            episode: 6,
          );
          final widget = buildHomeDetail(
            item: item,
            addon: addon,
            merged: merged,
            isTelevision: true,
            pikpakOnly: true,
            hasBoundSource: () {
              boundReads++;
              return true;
            },
            isTraktSource: true,
            isMdblistSource: true,
            heroTag: 'hero',
            initialSeason: 4,
            initialEpisode: 2,
            resumeInfo: () async {
              calls.add('resume');
              return (started: true, season: 5, episode: 6);
            },
            play:
                ({
                  bool startFromBeginning = false,
                  bool preferTraktResume = false,
                  bool skipEpisodeFallback = false,
                  bool browseSourcesOnly = false,
                  HomeDetailPromise? promisedTarget,
                }) async {
                  plays.add({
                    'rewatch': startFromBeginning,
                    'trakt': preferTraktResume,
                    'skip': skipEpisodeFallback,
                    'browse': browseSourcesOnly,
                    'promise': promisedTarget,
                  });
                },
            browse: () => calls.add('browse'),
            browseSelection: (value) {
              expect(value, same(selection));
              calls.add('selection-browse');
            },
            playSelection: (value) async {
              expect(value, same(selection));
              calls.add('selection-play');
            },
            boundSourceCount: (_) => 7,
            selectSource: (value) async {
              expect(value, same(item));
              calls.add('source');
            },
            adoptArtwork: (_) => calls.add('art'),
            menus: HomeDetailMenus(
              type: type,
              identity: item.id,
              removalColor: Colors.red,
              inLocalContinueWatching: false,
              inTraktContinueWatching: false,
              inMdblistContinueWatching: false,
              hasBoundSource: () => false,
              traktAuthenticated: () => false,
              simklAuthenticated: () => false,
              mdblistAuthenticated: () => false,
              hasSimklPause: () => false,
            ),
            traktAction: (action, {rating}) async =>
                calls.add('trakt:${action.name}:$rating'),
            traktStatus: () async {
              calls.add('trakt-status');
              return null;
            },
            simklAction: (action, {rating}) async =>
                calls.add('simkl:${action.name}:$rating'),
            simklStatus: () async {
              calls.add('simkl-status');
              return null;
            },
            mdblistAction: (action, {rating}) async =>
                calls.add('mdblist:${action.name}:$rating'),
            mdblistStatus: () async {
              calls.add('mdblist-status');
              return null;
            },
            recommendations: () async {
              calls.add('recommendations');
              return [item];
            },
            openRecommendation: (value) {
              expect(value, same(item));
              calls.add('recommendation');
            },
            enrich: (id, kind) async {
              expect((id, kind), ('tt123', type));
              calls.add('enrich');
              return item;
            },
          );
          expect(
            calls,
            isEmpty,
          ); // Construction must not start loads or actions.
          if (merged && type != 'tv') {
            final page = widget as MergedDetailScreen;
            expect(page.item, same(item));
            expect(page.addon, same(addon));
            expect(page.showQuickPlay, isTrue); // PikPak remains enabled here.
            expect(page.isTelevision, isTrue);
            expect((page.isTraktSource, page.isMdblistSource), (true, true));
            expect(
              (page.heroTag, page.initialSeason, page.initialEpisode),
              ('hero', 4, 2),
            );
            expect(boundReads, 0);
            expect(page.boundSourceCount!(item), 7);
            const promise = (started: true, season: 5, episode: 6);
            await page.onResume(promise);
            expect(plays.last, {
              'rewatch': false,
              'trakt': true,
              'skip': true,
              'browse': false,
              'promise': promise,
            });
            await page.onBrowsePrimaryEpisodeSources!(promise);
            expect(plays.last, {
              'rewatch': false,
              'trakt': true,
              'skip': true,
              'browse': true,
              'promise': promise,
            });
            await page.onRewatch!();
            expect(plays.last, {
              'rewatch': true,
              'trakt': false,
              'skip': false,
              'browse': false,
              'promise': null,
            });
            expect(page.onBrowse == null, type != 'movie');
            page.onBrowse?.call();
            page.onItemSelected!(selection);
            await page.onQuickPlay!(selection);
            await page.onSelectSource!(item);
            await page.onTraktRate!(8);
            await page.onSimklRate!(7);
            await page.onMdblistRate!(6);
            expect(
              calls,
              containsAll([
                'selection-browse',
                'selection-play',
                'source',
                'trakt:rate:8',
                'simkl:rate:7',
                'mdblist:rate:6',
              ]),
            );
            await page.traktStatusLoader!();
            await page.mdblistStatusLoader!();
            expect(await page.resumeInfoLoader!(), (
              started: true,
              season: 5,
              episode: 6,
            ));
            expect(await page.recommendationsLoader!(), [item]);
            page.onRecommendationTap!(item);
            expect(await page.metaEnricher!('tt123', type), same(item));
          } else {
            final page = widget as CatalogItemDetailScreen;
            expect(page.item.sourceAddon, same(addon));
            expect(page.item.id, item.id);
            expect(page.showQuickPlay, isFalse);
            expect(page.isTelevision, isTrue);
            expect(page.hasBoundSource, isTrue);
            expect(boundReads, 1);
            page.onPlay();
            expect(plays.last, {
              'rewatch': false,
              'trakt': true,
              'skip': false,
              'browse': false,
              'promise': null,
            });
            page.onRewatch!();
            expect(plays.last, {
              'rewatch': true,
              'trakt': false,
              'skip': false,
              'browse': false,
              'promise': null,
            });
            expect(
              page.onBrowsePrimaryEpisodeSources == null,
              type != 'series',
            );
            if (type == 'series') {
              await page.onBrowsePrimaryEpisodeSources!();
              expect(plays.last, {
                'rewatch': false,
                'trakt': true,
                'skip': true,
                'browse': true,
                'promise': null,
              });
            }
            page.onBrowse();
            expect(await page.resumeInfoLoader!(), (
              started: true,
              season: 5,
              episode: 6,
            ));
            await page.simklStatusLoader!();
            expect(await page.recommendationsLoader!(), [item]);
            page.onRecommendationTap!(item);
            expect(await page.metaEnricher!('tt123', type), same(item));
            expect(
              calls,
              containsAll([
                'browse',
                'resume',
                'simkl-status',
                'recommendations',
                'recommendation',
                'enrich',
              ]),
            );
            expect(calls, isNot(contains('trakt-status')));
          }
        },
      );
    }
  }
}
