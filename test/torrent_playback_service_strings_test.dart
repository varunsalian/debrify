import 'dart:io';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/cloud/cloud_capabilities.dart';
import 'package:debrify/services/cloud/cloud_port_feature.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/playback_service_dispatch.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/torrent_playback/playback_candidate_ranking.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/utils/filter_ladder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_cloud_provider.dart';

/// Fat-port fake that also implements [CloudCachedHashes] so `is` checks hit
/// (P1 FakeCloudProvider does not implement that type).
class _HashesCapFake extends FakeCloudProvider implements CloudCachedHashes {
  _HashesCapFake({required super.id});
}

class _CheckCacheCapFake extends FakeCloudProvider implements CloudCheckCache {
  _CheckCacheCapFake({required super.id});
}

void _installFakes({
  FakeCloudProvider? debrid,
  FakeCloudProvider? torbox,
  FakeCloudProvider? pikpak,
  FakeCloudProvider? premiumize,
  FakeCloudProvider? alldebrid,
}) {
  CloudProviderRegistry.instance = CloudProviderRegistry([
    debrid ?? FakeCloudProvider(id: CloudProviderId.debrid),
    torbox ?? FakeCloudProvider(id: CloudProviderId.torbox),
    pikpak ?? FakeCloudProvider(id: CloudProviderId.pikpak),
    premiumize ?? FakeCloudProvider(id: CloudProviderId.premiumize),
    alldebrid ?? FakeCloudProvider(id: CloudProviderId.alldebrid),
  ]);
}

Torrent _t(
  String name, {
  StreamType type = StreamType.torrent,
  String? coverageType,
}) => Torrent(
  rowid: 0,
  infohash: 'a' * 40,
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: type,
  coverageType: coverageType,
);

final _p1 = TorrentFilterState(
  qualities: {QualityTier.fullHd},
  ripSources: {RipSourceCategory.web, RipSourceCategory.bluRay},
  languages: {AudioLanguage.english},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(CloudProviderRegistry.debugReset);

  setUp(_installFakes);

  group('cache-first / hasCacheCheck', () {
    test('FakeCloudProvider: TorBox hashes or Premiumize flags only', () {
      expect(PlaybackServiceDispatch.hasCacheCheck('torbox'), isTrue);
      expect(PlaybackServiceDispatch.hasCacheCheck('premiumize'), isTrue);
      expect(PlaybackServiceDispatch.hasCacheCheck('debrid'), isFalse);
      expect(PlaybackServiceDispatch.hasCacheCheck('alldebrid'), isFalse);
      expect(PlaybackServiceDispatch.hasCacheCheck('pikpak'), isFalse);
      expect(PlaybackServiceDispatch.hasCacheCheck('realdebrid'), isFalse);
      expect(PlaybackServiceDispatch.hasCacheCheck('rd'), isFalse);
      expect(PlaybackServiceDispatch.hasCacheCheck('real_debrid'), isFalse);
      expect(PlaybackServiceDispatch.hasCacheCheck('mystery'), isFalse);
    });

    test('capability is-checks win over FakeCloudProvider.supports table', () {
      _installFakes(
        debrid: _HashesCapFake(id: CloudProviderId.debrid),
        alldebrid: _CheckCacheCapFake(id: CloudProviderId.alldebrid),
        torbox: FakeCloudProvider(id: CloudProviderId.torbox),
      );
      expect(
        CloudPortFeature.forProvider(
          CloudProviderId.debrid,
        ).contains(CloudPortFeature.cachedHashes),
        isFalse,
      );
      expect(PlaybackServiceDispatch.hasCacheCheck('debrid'), isTrue);
      expect(
        CloudPortFeature.forProvider(
          CloudProviderId.alldebrid,
        ).contains(CloudPortFeature.checkCache),
        isFalse,
      );
      expect(PlaybackServiceDispatch.hasCacheCheck('alldebrid'), isTrue);
      expect(
        CloudPortFeature.forProvider(
          CloudProviderId.torbox,
        ).contains(CloudPortFeature.cachedHashes),
        isTrue,
      );
      expect(PlaybackServiceDispatch.hasCacheCheck('torbox'), isTrue);
    });

    test('production adapters: TorBox hashes and Premiumize flags', () {
      CloudProviderRegistry.debugReset();
      expect(PlaybackServiceDispatch.hasCacheCheck('torbox'), isTrue);
      expect(PlaybackServiceDispatch.hasCacheCheck('premiumize'), isTrue);
      expect(PlaybackServiceDispatch.hasCacheCheck('debrid'), isFalse);
      expect(PlaybackServiceDispatch.hasCacheCheck('alldebrid'), isFalse);
      expect(PlaybackServiceDispatch.hasCacheCheck('pikpak'), isFalse);
    });
  });

  group('PikPak one-probe / pack-top / series skip', () {
    test('probeAttemptCount: pikpak is 1 no matter what', () {
      expect(
        PlaybackCandidateRanking.probeAttemptCount(
          'pikpak',
          tryMultiple: true,
          maxRetries: 10,
          minAttempts: 2,
        ),
        1,
      );
      expect(PlaybackServiceDispatch.oneProbeSafety('pikpak'), isTrue);
      expect(PlaybackServiceDispatch.oneProbeSafety('debrid'), isFalse);
      expect(PlaybackServiceDispatch.oneProbeSafety('torbox'), isFalse);
      expect(PlaybackServiceDispatch.isPikPak('PikPak'), isFalse);
      expect(PlaybackServiceDispatch.isPikPak('realdebrid'), isFalse);
    });

    test(
      'packTopSafety: pikpak hoists the single to index 0, others index 1',
      () {
        final ladder = FilterLadder(_p1);
        final pack = _t(
          'Breaking.Bad.Complete.S01-S05.1080p.10bit.BluRay.x265.HEVC.6CH-M',
          coverageType: 'completeSeries',
        );
        final pack2 = _t(
          'Breaking Bad S01-S05 Seasons 1-5 Complete 1080p H264 BluRay-MIXE',
          coverageType: 'multiSeasonPack',
        );
        final single = _t('Breaking.Bad.S01E01.720p.HDTV.x264');

        final (
          debridList,
          debridAttempts,
        ) = PlaybackCandidateRanking.packTopSafety(
          [pack, pack2, single],
          provider: 'debrid',
          ladder: ladder,
          season: 1,
          episode: 1,
        );
        expect(debridList, [pack, single, pack2]);
        expect(debridAttempts, 2);

        final (
          pikpakList,
          pikpakAttempts,
        ) = PlaybackCandidateRanking.packTopSafety(
          [pack, pack2, single],
          provider: 'pikpak',
          ladder: ladder,
          season: 1,
          episode: 1,
        );
        expect(pikpakList, [single, pack, pack2]);
        expect(pikpakAttempts, 1);
      },
    );

    test('series auto-pin / rebind / pack-first skip PikPak torrents only', () {
      expect(PlaybackServiceDispatch.skipSeriesTorrentPin('pikpak'), isTrue);
      expect(PlaybackServiceDispatch.skipSeriesTorrentPin('debrid'), isFalse);
      expect(PlaybackServiceDispatch.skipSeriesTorrentPin('torbox'), isFalse);
      expect(
        PlaybackServiceDispatch.skipSeriesTorrentPin('premiumize'),
        isFalse,
      );
      expect(
        PlaybackServiceDispatch.skipSeriesTorrentPin('alldebrid'),
        isFalse,
      );
    });
  });

  group('skip-orphan delete', () {
    test('RD and PikPak delete; TorBox / Premiumize / AllDebrid do not', () {
      expect(PlaybackServiceDispatch.deletesRdOrphan('debrid'), isTrue);
      expect(PlaybackServiceDispatch.deletesRdOrphan('rd'), isFalse);
      expect(PlaybackServiceDispatch.deletesRdOrphan('realdebrid'), isFalse);
      expect(PlaybackServiceDispatch.deletesPikPakOrphan('pikpak'), isTrue);
      expect(PlaybackServiceDispatch.deletesPikPakOrphan('debrid'), isFalse);
      expect(PlaybackServiceDispatch.deletesRdOrphan('torbox'), isFalse);
      expect(PlaybackServiceDispatch.deletesRdOrphan('premiumize'), isFalse);
      expect(PlaybackServiceDispatch.deletesRdOrphan('alldebrid'), isFalse);
    });
  });

  group('bound provider set and RD stored mapping', () {
    test('storedId set is rd + four names + local + addon-direct', () {
      const supported = {
        'rd',
        'torbox',
        'premiumize',
        'alldebrid',
        'pikpak',
        SeriesSource.localService,
        SeriesSource.addonDirectService,
      };
      for (final stored in supported) {
        expect(
          PlaybackServiceDispatch.boundProviderSupported(stored),
          isTrue,
          reason: stored,
        );
      }
      expect(PlaybackServiceDispatch.boundProviderSupported('debrid'), isFalse);
      expect(
        PlaybackServiceDispatch.boundProviderSupported('realdebrid'),
        isFalse,
      );
      expect(
        PlaybackServiceDispatch.boundProviderSupported('real_debrid'),
        isFalse,
      );
      expect(
        PlaybackServiceDispatch.boundProviderSupported('mystery'),
        isFalse,
      );
      expect(SeriesSource.localService, 'local');
      expect(SeriesSource.addonDirectService, 'stremio_direct');
    });

    test("RD stored mapping stays 'rd' <-> 'debrid'", () {
      expect(TorrentPlaybackService.storedProviderKey('debrid'), 'rd');
      expect(TorrentPlaybackService.storedProviderKey('torbox'), 'torbox');
      expect(TorrentPlaybackService.storedProviderKey('webdav'), 'webdav');
      expect(PlaybackServiceDispatch.storedProviderKey('debrid'), 'rd');
      expect(PlaybackServiceDispatch.providerFromStored('rd'), 'debrid');
      expect(PlaybackServiceDispatch.providerFromStored('debrid'), 'debrid');
      expect(CloudProviderId.fromStoredId('rd'), CloudProviderId.debrid);
      expect(CloudProviderId.fromStoredId('debrid'), isNull);
      expect(CloudProviderId.fromPlaybackId('debrid'), CloudProviderId.debrid);
      expect(CloudProviderId.fromPlaybackId('rd'), isNull);
    });
  });

  group('power-action tiles and credential keys', () {
    test('TorBox ZIP tiles vs Premiumize transfer tiles', () {
      expect(PlaybackServiceDispatch.showTorboxPowerActions('torbox'), isTrue);
      expect(
        PlaybackServiceDispatch.showTorboxPowerActions('premiumize'),
        isFalse,
      );
      expect(
        PlaybackServiceDispatch.showPremiumizePowerActions('premiumize'),
        isTrue,
      );
      expect(
        PlaybackServiceDispatch.showPremiumizePowerActions('torbox'),
        isFalse,
      );
      expect(PlaybackServiceDispatch.showTorboxPowerActions('debrid'), isFalse);
      expect(PlaybackServiceDispatch.showTorboxPowerActions('pikpak'), isFalse);
    });

    test('DownloadService credential keys stay byte-identical', () {
      expect(
        DownloadService.credentialKeyForCloudProvider(
          CloudProviderId.premiumize.playbackId,
        ),
        'premiumize_api_key',
      );
      expect(
        DownloadService.credentialKeyForCloudProvider(
          CloudProviderId.torbox.playbackId,
        ),
        'torbox_api_key',
      );
      expect(CloudProviderId.torbox.credentialKey, 'torbox_api_key');
      expect(CloudProviderId.premiumize.credentialKey, 'premiumize_api_key');
    });
  });

  test('owned file has no provider-id string literals outside comments', () {
    const path = 'lib/services/torrent_playback_service.dart';
    final source = File(path).readAsStringSync();
    final withoutBlock = source.replaceAll(
      RegExp(r'/\*.*?\*/', dotAll: true),
      '',
    );
    final withoutLine = withoutBlock
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    final hits = RegExp(
      r"'(realdebrid|real_debrid|torbox|premiumize|alldebrid|pikpak)'",
    ).allMatches(withoutLine).map((m) => m.group(0)).toList();
    expect(hits, isEmpty, reason: '$path string-match leftovers: $hits');
    expect(source.contains('PlaybackServiceDispatch.hasCacheCheck'), isTrue);
    expect(source.contains('PlaybackServiceDispatch.oneProbeSafety'), isTrue);
    expect(
      source.contains('PlaybackServiceDispatch.boundProviderSupported'),
      isTrue,
    );
    expect(
      source.contains('PlaybackServiceDispatch.showTorboxPowerActions'),
      isTrue,
    );
    expect(
      source.contains('PlaybackServiceDispatch.showPremiumizePowerActions'),
      isTrue,
    );
    expect(source.contains('CloudProviderId.premiumize.playbackId'), isTrue);
    expect(source.contains('CloudProviderId.torbox.playbackId'), isTrue);
  });
}
