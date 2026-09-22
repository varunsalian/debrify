import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/local_playback_resume_resolver.dart';
import 'package:debrify/services/local_series_completion_service.dart';
import 'package:debrify/services/next_episode_service.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/series_progress_reset_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_preference_portability.dart';
import 'package:debrify/services/hide_watched_prefs.dart';
import 'package:debrify/services/watched_filter.dart';
import 'package:debrify/services/watched_status_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/stremio_subtitle_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/watched_action_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final custom = const CustomSeriesIdentity('config-a', 'OnePace').id;
  final other = const CustomSeriesIdentity('config-b', 'OnePace').id;
  const canonical = 'tt0388629';
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> save(String id, int position, {int episode = 1}) =>
      StorageService.saveSeriesPlaybackState(
        seriesTitle: 'Same title',
        season: 1,
        episode: episode,
        positionMs: position,
        durationMs: 100000,
        imdbId: id,
      );

  test('identity survives case normalization and separates configurations', () {
    expect(CustomSeriesIdentity.resumeBookmarkKey(canonical, 1, 1), isNull);
    expect(CustomSeriesIdentity.resumeBookmarkKey(custom, 1, 1),
        isNot(CustomSeriesIdentity.resumeBookmarkKey(other, 1, 1)));
    expect(CustomSeriesIdentity.resumeBookmarkKey(custom, 1, 1),
        isNot(CustomSeriesIdentity.resumeBookmarkKey(custom, 1, 2)));
    expect(
      CustomSeriesIdentity.parse(custom.toLowerCase())!.catalogId,
      'OnePace',
    );
    expect(custom, isNot(other));
    expect(CustomSeriesIdentity.parse('custom-series:xyz'), isNull);
    final selection =
        const AdvancedSearchSelection(
          imdbId: canonical,
          isSeries: true,
          title: 'Edit',
          season: 1,
          episode: 1,
          traktSource: true,
          traktProgressPercent: 75,
        ).withStremioEpisodeIdentity(
          addonId: 'edit',
          addonKey: 'config-a',
          catalogId: 'OnePace',
          videoId: 'cut-1',
        );
    expect(selection.imdbId, custom);
    expect(selection.traktSource, isFalse);
    expect(selection.traktProgressPercent, isNull);
    expect(selection.scopedToSeason(2).imdbId, custom);
    final meta = StremioMeta(
      id: 'OnePace',
      imdbId: custom,
      type: 'series',
      name: 'Edit',
    );
    expect(StremioMeta.fromJson(meta.toJson()).imdbId, custom);
  });

  test(
    'same titles and coordinates keep independent resume and watched state',
    () async {
      await save(canonical, 1000);
      await save(custom, 2000);
      await save(other, 3000);
      for (final entry in {
        canonical: 1000,
        custom: 2000,
        other: 3000,
      }.entries) {
        final state = await LocalPlaybackResumeResolver.episode(
          seriesTitle: 'Same title',
          season: 1,
          episode: 1,
          imdbId: entry.key,
          policy: PlaybackResumePolicy.catalogCanonical,
        );
        expect(state?['positionMs'], entry.value);
      }
      await WatchedActionCoordinator.setEpisodeWatched(
        imdbId: custom,
        seriesTitle: 'Same title',
        season: 1,
        episode: 1,
        watched: true,
        forceTargets: {TrackingSource.trakt, TrackingSource.simkl},
      );
      expect(
        await StorageService.getMergedFinishedEpisodes(
          seriesTitle: 'Same title',
          imdbId: canonical,
        ),
        isEmpty,
      );
      expect(
        await StorageService.getMergedFinishedEpisodes(
          seriesTitle: 'Same title',
          imdbId: other,
        ),
        isEmpty,
      );
      expect(
        (await StorageService.getMergedFinishedEpisodes(
          seriesTitle: 'Same title',
          imdbId: custom,
        ))['1'],
        {1},
      );
      await StorageService.unmarkSeriesAsFinished(
        canonical,
        seriesTitle: 'Same title',
      );
      expect(
        (await StorageService.getMergedFinishedEpisodes(
          seriesTitle: 'Same title',
          imdbId: custom,
        ))['1'],
        {1},
      );
    },
  );

  test('custom resume never borrows legacy title records', () async {
    await save(canonical, 1000);
    expect(
      await LocalPlaybackResumeResolver.episode(
        seriesTitle: 'Same title',
        season: 1,
        episode: 1,
        imdbId: custom,
        policy: PlaybackResumePolicy.catalogCanonical,
      ),
      isNull,
    );
  });

  test(
    'clearing custom progress leaves original and other configuration intact',
    () async {
      await save(canonical, 1000);
      await save(custom, 2000);
      await save(other, 3000);
      await StorageService.clearSeriesWatchProgress(custom, 'Same title');
      expect(await StorageService.getLastPlayedEpisodeByImdbId(custom), isNull);
      expect(
        (await StorageService.getLastPlayedEpisodeByImdbId(
          canonical,
        ))?['positionMs'],
        1000,
      );
      expect(
        (await StorageService.getLastPlayedEpisodeByImdbId(
          other,
        ))?['positionMs'],
        3000,
      );
    },
  );

  test(
    'CW stores independently and carries reversible origin identity',
    () async {
      for (final id in [canonical, custom, other]) {
        await StorageService.saveContinueWatchingItem(
          imdbId: id,
          title: 'Same title',
          contentType: 'series',
        );
      }
      final rows = await StorageService.getContinueWatchingItems();
      expect(rows.length, 3);
      final restored = CustomSeriesIdentity.parse(
        rows.first['imdbId'] as String,
      )!;
      expect(restored.addonKey, 'config-b');
      expect(restored.catalogId, 'OnePace');
      await StorageService.removeContinueWatchingItem(custom);
      expect(
        (await StorageService.getContinueWatchingItems())
            .map((m) => m['imdbId'])
            .toSet(),
        {canonical, other},
      );
    },
  );

  test(
    'dedicated tracker policy falls back to local only for custom content',
    () {
      const policy = TrackingSourcePolicy(
        scrobbleTargets: {TrackingSource.simkl},
        progressSource: WatchProgressSource.simkl,
        homeTickSources: {TrackingSource.simkl},
      );
      expect(policy.forContent(custom).forcesLocalCompletion, isTrue);
      expect(
        policy.forContent(custom).scrobbles(TrackingSource.simkl),
        isFalse,
      );
      expect(policy.forContent(canonical), same(policy));
    },
  );

  test('custom subtitles do not query canonical addons', () async {
    expect(
      await StremioSubtitleService.instance.fetchSubtitleSlots(
        type: 'series',
        imdbId: custom,
        season: 1,
        episode: 1,
      ),
      isEmpty,
    );
  });

  test('same addon configuration keeps progress identity across devices', () {
    StremioAddon configured(String resource) => StremioAddon(
      id: 'same-addon',
      name: 'Edit',
      manifestUrl: 'https://example.test/a/manifest.json',
      baseUrl: 'https://example.test/a',
      connectionResourceId: resource,
    );
    const item = StremioMeta(
      id: 'OnePace',
      imdbId: canonical,
      type: 'series',
      name: 'Edit',
    );
    final first = item.withCustomSeriesIdentity(configured('device-a'));
    final second = item.withCustomSeriesIdentity(configured('device-b'));
    expect(first.imdbId, second.imdbId);
    final selection =
        AdvancedSearchSelection(
          imdbId: first.imdbId!,
          isSeries: true,
          title: 'Edit',
        ).withStremioEpisodeIdentity(
          addonId: 'same-addon',
          addonKey: configured('device-b').sourceBindingKey,
          catalogId: 'OnePace',
          videoId: 'cut-1',
        );
    expect(selection.imdbId, first.imdbId);
  });

  test('full reset of custom show only clears its own local history', () async {
    await save(canonical, 1000);
    await save(custom, 2000);
    await StorageService.saveContinueWatchingItem(
      imdbId: custom,
      title: 'Same title',
      contentType: 'series',
    );
    expect(
      await SeriesProgressResetService.clear(custom, 'Same title'),
      isEmpty,
    );
    expect(await StorageService.getContinueWatchingItems(), isEmpty);
    expect(
      (await StorageService.getLastPlayedEpisodeByImdbId(
        canonical,
      ))?['positionMs'],
      1000,
    );
  });

  test('existing pins migrate only their exact custom configuration', () async {
    final pin = SeriesSource(
      torrentHash: 'abc',
      torrentName: 'Edit',
      debridService: 'rd',
      debridTorrentId: '1',
      boundAt: 1,
      addonCatalogId: 'OnePace',
      addonCatalogKey: 'config-a',
    );
    const original = SeriesSource(
      torrentHash: 'def',
      torrentName: 'Original',
      debridService: 'rd',
      debridTorrentId: '2',
      boundAt: 1,
    );
    await SeriesSourceService.addSource(canonical, original);
    await SeriesSourceService.addSource(canonical, pin);
    expect(
      (await SeriesSourceService.getSources(custom)).single.bindingKey,
      pin.bindingKey,
    );
    expect(
      (await SeriesSourceService.getSources(canonical)).single.bindingKey,
      original.bindingKey,
    );
    expect(await SeriesSourceService.getSources(other), isEmpty);
    await SeriesSourceService.removeSourceEntry(custom, pin);
    expect(await SeriesSourceService.getSources(custom), isEmpty);
  });

  test('long custom pin keys survive portable backup and restore', () async {
    final id = CustomSeriesIdentity('a' * 64, 'catalog-' + 'b' * 200).id;
    final key = 'series_source_$id';
    expect(key.length, greaterThan(256));
    const pin = SeriesSource(torrentHash: 'abc', torrentName: 'Edit',
        debridService: 'rd', debridTorrentId: '1', boundAt: 1);
    await SeriesSourceService.addSource(id, pin);
    final prefs = await SharedPreferences.getInstance();
    final portable = ProfilePreferencePortability.prepareValue(key, prefs.getString(key));
    expect(portable.include, isTrue);
    SharedPreferences.setMockInitialValues({key: portable.value!});
    expect((await SeriesSourceService.getSources(id)).single.bindingKey, pin.bindingKey);
    expect(ProfilePreferencePortability.allowsKey('x' * 300), isFalse);
    expect(ProfilePreferencePortability.allowsKey('series_source_custom-series:' + 'z' * 300), isFalse);
  });

  test('catalog identity, next and completion use custom inventory', () async {
    final previousHttp = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousHttp);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    var metadataUnavailable = false;
    server.listen((r) async {
      paths.add(r.uri.path);
      if (metadataUnavailable || r.uri.path.contains('tt9999999')) {
        r.response.statusCode = 503;
        await r.response.close();
        return;
      }
      if (r.uri.path.contains(canonical)) {
        await Future<void>.delayed(const Duration(milliseconds: 4200));
      }
      r.response.headers.contentType = ContentType.json;
      r.response.write(
        jsonEncode({
          'meta': {
            'videos': (r.uri.path.contains('tt7654321') || r.uri.path.contains('ordinary-slug'))
                ? [
                    {'id': 'tt7654321:1:1', 'season': 1, 'episode': 1},
                  ]
                : [
                    {'id': 'cut-1', 'season': 3, 'episode': 7},
                    {'id': 'cut-2', 'season': 3, 'episode': 9},
                  ],
          },
        }),
      );
      await r.response.close();
    });
    addTearDown(() => server.close(force: true));
    final base = 'http://127.0.0.1:${server.port}';
    final addon = StremioAddon(
      id: 'edit',
      name: 'Edit',
      baseUrl: base,
      manifestUrl: '$base/manifest.json',
      resources: ['meta', 'stream'],
      types: ['series'],
    );
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode([addon.toJson()]),
    });
    final service = StremioService.instance..invalidateCache();
    addTearDown(service.invalidateCache);
    final rawCard = const StremioMeta(
      id: canonical, imdbId: canonical, type: 'series', name: 'Other edit',
    ).withSourceAddon(addon);
    expect(service.catalogProgressIdentity(rawCard), canonical);
    var badgeRefreshes = 0;
    void refreshBadge() => badgeRefreshes++;
    service.catalogProgressRevision.addListener(refreshBadge);
    addTearDown(() => service.catalogProgressRevision.removeListener(refreshBadge));
    final item = await service.scopeSeriesProgress(
      const StremioMeta(
        id: 'OnePace',
        imdbId: canonical,
        type: 'series',
        name: 'Edit',
      ),
      addon,
    );
    expect(item.id, 'OnePace');
    expect(
      CustomSeriesIdentity.parse(item.imdbId)!.addonKey,
      addon.portableConfigurationKey,
    );
    expect(await NextEpisodeService.findNextEpisode(item.imdbId!, 3, 7), (
      season: 3,
      episode: 9,
    ));
    expect(
      paths.every((p) => p.contains('OnePace') && !p.contains(canonical)),
      isTrue,
    );
    // The same canonical-looking parent ID can still contain custom videos.
    final sameParent = await service.scopeSeriesProgress(
      const StremioMeta(
        id: canonical,
        imdbId: canonical,
        type: 'series',
        name: 'Other edit',
      ),
      addon,
    );
    expect(CustomSeriesIdentity.isCustom(sameParent.imdbId), isTrue);
    expect(service.catalogProgressIdentity(rawCard), sameParent.imdbId);
    expect(badgeRefreshes, greaterThan(0));
    expect(CustomSeriesIdentity.parse(sameParent.imdbId)!.addonKey,
        addon.portableConfigurationKey);
    final warmParent = await service.scopeSeriesProgress(
      const StremioMeta(id: canonical, imdbId: canonical,
          type: 'series', name: 'Other edit'), addon,
    );
    expect(warmParent.imdbId, sameParent.imdbId);
    await expectLater(service.scopeSeriesProgress(
      const StremioMeta(id: 'tt9999999', imdbId: 'tt9999999',
          type: 'series', name: 'Unavailable'), addon,
    ), throwsStateError);
    const original = StremioMeta(
      id: 'tt7654321',
      imdbId: 'tt7654321',
      type: 'series',
      name: 'Original',
    );
    expect(await service.scopeSeriesProgress(original, addon), same(original));
    expect(service.catalogProgressIdentity(original.withSourceAddon(addon)),
        original.imdbId);
    const aliasedOriginal = StremioMeta(id: 'ordinary-slug', imdbId: 'tt7654321',
        type: 'series', name: 'Original');
    metadataUnavailable = true;
    final firstAttemptRequests = paths.length;
    await expectLater(service.scopeSeriesProgress(aliasedOriginal, addon), throwsStateError);
    expect(paths.length, greaterThan(firstAttemptRequests));
    final prefsAfterFailure = await SharedPreferences.getInstance();
    expect(prefsAfterFailure.getString(
        'catalog_progress_identity_v1:${addon.portableConfigurationKey}:ordinary-slug'), isNull);
    metadataUnavailable = false;
    expect(await service.scopeSeriesProgress(aliasedOriginal, addon), same(aliasedOriginal));
    final unmappedCard = const StremioMeta(id: 'unmapped-edit',
        type: 'series', name: 'Unmapped edit').withSourceAddon(addon);
    expect(unmappedCard.effectiveImdbId, isNull);
    final unmapped = await service.scopeSeriesProgress(unmappedCard, addon);
    metadataUnavailable = true;
    service.invalidateCache();
    final requestsBeforeFailure = paths.length;
    expect(await service.scopeSeriesProgress(original, addon), same(original));
    expect(paths.length, greaterThan(requestsBeforeFailure));
    expect(await service.scopeSeriesProgress(aliasedOriginal, addon), same(aliasedOriginal));
    expect((await service.scopeSeriesProgress(rawCard, addon)).imdbId,
        sameParent.imdbId);
    expect(await service.restoredCatalogProgressIdentity(rawCard), sameParent.imdbId);
    // A cold catalog filter must use the same identity as the badge, not the
    // original show's completed state.
    await StorageService.setSeriesExplicitlyWatched(canonical, watched: true);
    await HideWatchedPrefs.setEnabled(true);
    service.invalidateCache();
    final watchedStatus = WatchedStatusService.instance..resetProfileScope();
    watchedStatus.ensureStarted();
    await watchedStatus.firstSnapshot;
    expect(WatchedFilter.hides(rawCard), isFalse);
    expect(WatchedFilter.hides(unmappedCard), isFalse);
    await StorageService.setSeriesExplicitlyWatched(sameParent.imdbId!, watched: true);
    await StorageService.setSeriesExplicitlyWatched(unmapped.imdbId!, watched: true);
    service.invalidateCache();
    watchedStatus.resetProfileScope();
    watchedStatus.ensureStarted();
    await watchedStatus.firstSnapshot;
    expect(WatchedFilter.hides(rawCard), isTrue);
    expect(WatchedFilter.hides(unmappedCard), isTrue);
    expect(await service.restoredCatalogProgressIdentity(unmappedCard), unmapped.imdbId);
    await HideWatchedPrefs.setEnabled(false);
    await LocalSeriesCompletionService.instance.recordRawEpisodeInventory(
      imdbId: item.imdbId!,
      seriesTitle: 'Edit',
      videos: [
        {'season': 3, 'episode': 7},
        {'season': 3, 'episode': 9},
      ],
    );
    for (final episode in [7, 9]) {
      await StorageService.markEpisodeAsFinished(
        seriesTitle: 'Edit',
        season: 3,
        episode: episode,
        imdbId: item.imdbId,
      );
    }
    expect(
      await LocalSeriesCompletionService.instance.caughtUpIds(),
      contains(item.imdbId),
    );
  });
}
