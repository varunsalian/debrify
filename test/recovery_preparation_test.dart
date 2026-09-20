import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/startup_recovery_sources.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/utils/filter_ladder.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent row(
  String name, {
  String? hash,
  String source = 'engine',
  String? url,
  String? addon,
}) => Torrent(
  rowid: 0,
  infohash: hash ?? name,
  name: name,
  sizeBytes: 100000000,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: source,
  directUrl: url,
  stremioAddonId: addon,
  streamType: url == null ? StreamType.torrent : StreamType.directUrl,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'strict 4K eligibility sees both raw representations and native uses the winner',
    () async {
      final low = row(
        'Movie 1080p',
        hash: 'a' * 40,
        source: 'stremio:AIOStreams',
      );
      final high = row('Movie 2160p', hash: 'a' * 40, source: 'comet');
      final rules = QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
        relaxFilters: false,
        sourcePriority: ['stremio:aiostreams', 'engine:comet'],
      );
      var manualCalls = 0;
      final fetcher = SeriesSourceFetcher.movie(
        searchMovie: () async {
          manualCalls++;
          return [low];
        },
        searchForRecovery: (_, __, ___) async => [low, high],
      );
      final raw = (await fetcher.fetch('movie', automaticRecovery: true))!;
      final automatic = await TorrentPlaybackService.prepareRecoverySources(
        raw,
        rules: rules,
        provider: 'debrid',
        ladder: FilterLadder(
          TorrentFilterState(qualities: {QualityTier.ultraHd}),
        ),
      );
      final merged = StartupRecoverySources.merge(
        existing: [],
        fetched: raw,
        automatic: automatic,
      );
      expect(manualCalls, 0);
      expect(automatic, [high]);
      expect(merged.sources[merged.automaticIndices.single], same(high));
      expect(await fetcher.fetch('movie'), [low]);
      final laterStage = StartupRecoverySources.merge(
        existing: [low],
        fetched: raw,
        automatic: automatic,
        replaceExistingAutomatic: true,
      );
      expect(laterStage.automaticIndices, [0]);
      expect(laterStage.sources.single, same(high));
    },
  );

  for (final provider in ['torbox', 'premiumize']) {
    test(
      '$provider cache hits lead exact-order and ready-first recovery',
      () async {
        for (final ranking in [
          QuickPlayRanking.exactOrder,
          QuickPlayRanking.readyFirst,
        ]) {
          final cold = row('Cold'), cached = row('Cached');
          var called = false;
          final prepared = await TorrentPlaybackService.prepareRecoverySources(
            [cold, cached],
            provider: provider,
            rules: QuickPlayRules.debrifyDefault(
              isMovie: true,
            ).copyWith(ranking: ranking),
            ladder: FilterLadder(TorrentFilterState()),
            cacheCheck: (actual, candidates) async {
              expect(actual, provider);
              expect(candidates, [cold, cached]);
              called = true;
              return [cached, cold];
            },
          );
          expect(called, isTrue);
          expect(prepared, [cached, cold]);
        }
      },
    );
  }

  test(
    'direct validation rejects placeholders and shares its bounded budget',
    () async {
      var probes = 0;
      final preflight = RecoveryDirectPreflight(
        budget: 2,
        isMovie: false,
        shouldProbe: TorrentPlaybackService.shouldPreflightDirectStream,
        probe: (url, {minBytes = 0, lenient = false, headers}) async {
          probes++;
          expect(minBytes, 10 * 1024 * 1024);
          expect(lenient, isTrue);
          return false;
        },
      );
      final failed = row('One', url: 'https://test/one');
      expect(await preflight.allows(failed, enabled: true), isFalse);
      expect(await preflight.allows(failed, enabled: true), isFalse);
      expect(
        await preflight.allows(
          row('Two', url: 'https://test/two'),
          enabled: true,
        ),
        isFalse,
      );
      expect(
        await preflight.allows(
          row('Three', url: 'https://test/three'),
          enabled: true,
        ),
        isTrue,
      );
      expect(probes, 2);
    },
  );

  test('disabled validation, AIOStreams, and IPTV bypass preflight', () async {
    final preflight = RecoveryDirectPreflight(
      budget: 5,
      isMovie: true,
      shouldProbe: TorrentPlaybackService.shouldPreflightDirectStream,
      probe: (_, {minBytes = 0, lenient = false, headers}) async =>
          throw StateError('must not probe'),
    );
    expect(
      await preflight.allows(
        row('AIO', url: 'https://cdn/test', addon: 'com.aiostreams'),
        enabled: true,
      ),
      isTrue,
    );
    expect(
      await preflight.allows(
        row(
          'IPTV',
          source: 'iptv:provider-id',
          url: 'https://iptv.test/episode',
        ),
        enabled: true,
      ),
      isTrue,
    );
    expect(
      await preflight.allows(
        row('Off', url: 'https://cdn/other'),
        enabled: false,
      ),
      isTrue,
    );
    expect(preflight.budget, 5);
  });

  test(
    'not-ready acquisition cleanup targets the correct provider and id',
    () async {
      final calls = <String>[];
      Future<void> rd(String key, String id) async {
        calls.add('rd:$key:$id');
      }

      Future<void> ad(String key, String id) async {
        calls.add('ad:$key:$id');
      }

      await TorrentPlaybackService.cleanupFailedAutomaticAcquisition(
        TorrentNotCachedException('torrent', 'rd-key'),
        deleteRealDebrid: rd,
        deleteAllDebrid: ad,
      );
      await TorrentPlaybackService.cleanupFailedAutomaticAcquisition(
        AllDebridTorrentNotReadyException('magnet', 'ad-key'),
        deleteRealDebrid: rd,
        deleteAllDebrid: ad,
      );
      expect(calls, ['rd:rd-key:torrent', 'ad:ad-key:magnet']);
      await TorrentPlaybackService.cleanupFailedAutomaticAcquisition(
        TorrentNotCachedException('torrent', 'key'),
        deleteRealDebrid: (_, __) async => throw StateError('cleanup failed'),
      );
      await TorrentPlaybackService.cleanupFailedAutomaticAcquisition(
        StateError('network'),
        deleteRealDebrid: rd,
        deleteAllDebrid: ad,
      );
      expect(calls.length, 2);
    },
  );
}
