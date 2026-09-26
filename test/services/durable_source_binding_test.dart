import 'package:debrify/models/series_source.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/durable_source_binding.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent row({
  StreamType type = StreamType.directUrl,
  String hash = 'AbC',
  String? addon = 'addon',
  String? addonKey = 'configuration',
  String? stream = 'stream',
  int? index,
  String? playlist = 'playlist',
  String? catalogType = 'series',
  String? entry = 'entry',
}) => Torrent(
  rowid: 0,
  infohash: hash,
  name: 'Source',
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: type,
  directUrl: 'https://example.invalid/video?token=temporary-secret',
  httpHeaders: {'Authorization': 'private-header'},
  stremioAddonId: addon,
  stremioAddonKey: addonKey,
  stremioStreamKey: stream,
  stremioStreamIndex: index,
  stremioBingeGroup: 'group',
  iptvPlaylistId: playlist,
  iptvCatalogType: catalogType,
  iptvEntryKey: entry,
);

SeriesSource? bind(
  Torrent source, {
  bool iptv = false,
  String provider = 'debrid',
}) => durableSourceBinding(
  source,
  provider,
  now: 42,
  isMediaServer: (_) => false,
  mediaServerBinding: (_) => throw StateError('Unexpected media lookup'),
  isIptv: (_) => iptv,
  storedProviderKey: (value) => value == 'debrid' ? 'rd' : value,
  addonCatalogId: 'catalog',
  addonCatalogKey: 'catalog-configuration',
);

void main() {
  for (final hasBinding in [true, false]) {
    test('media classification wins without fallback, binding=$hasBinding', () {
      const pin = SeriesSource(
        torrentHash: '',
        torrentName: 'Media',
        debridService: SeriesSource.mediaServerService,
        debridTorrentId: 'item',
        boundAt: 9,
      );
      final calls = <String>[];
      final result = durableSourceBinding(
        row(),
        'ignored',
        now: 42,
        isMediaServer: (_) {
          calls.add('media');
          return true;
        },
        mediaServerBinding: (_) {
          calls.add('binding');
          return hasBinding ? pin : null;
        },
        isIptv: (_) => throw StateError('Unexpected IPTV fallback'),
        storedProviderKey: (_) =>
            throw StateError('Unexpected provider mapping'),
      );
      expect(result, same(hasBinding ? pin : null));
      expect(calls, ['media', 'binding']);
    });
  }

  test('IPTV stores catalog identity without stream credentials', () {
    final pin = bind(row(), iptv: true)!;
    expect(pin.debridService, SeriesSource.iptvDirectService);
    expect(pin.iptvPlaylistId, 'playlist');
    expect(pin.iptvCatalogType, 'series');
    expect(pin.iptvEntryKey, 'entry');
    expect(pin.torrentHash, isEmpty);
    expect(pin.boundAt, 42);
    expect(pin.addonId, isNull);
    expect(pin.toJson().toString(), isNot(contains('temporary-secret')));
    expect(pin.toJson().toString(), isNot(contains('private-header')));
  });

  for (final missing in <String?>[null, '']) {
    test('incomplete direct provenance is rejected for $missing', () {
      for (final source in [
        row(playlist: missing),
        row(catalogType: missing),
        row(entry: missing),
      ]) {
        expect(bind(source, iptv: true), isNull);
      }
      for (final source in [
        row(addon: missing),
        row(addonKey: missing),
        row(stream: missing),
      ]) {
        expect(bind(source), isNull);
      }
    });
  }

  for (final index in <int?>[null, 7]) {
    test('addon provenance and stream index survive, index=$index', () {
      final pin = bind(row(index: index))!;
      expect(pin.debridService, SeriesSource.addonDirectService);
      expect(pin.addonId, 'addon');
      expect(pin.addonKey, 'configuration');
      expect(pin.streamKey, 'stream');
      expect(pin.streamIndex, index ?? 0);
      expect(pin.bingeGroup, 'group');
      expect(pin.addonCatalogId, 'catalog');
      expect(pin.addonCatalogKey, 'catalog-configuration');
      expect(pin.boundAt, 42);
      expect(pin.toJson().toString(), isNot(contains('temporary-secret')));
      expect(pin.toJson().toString(), isNot(contains('private-header')));
    });
  }

  test(
    'torrent descriptors preserve raw hash, provider mapping and catalog',
    () {
      final pin = bind(row(type: StreamType.torrent))!;
      expect(pin.torrentHash, 'AbC');
      expect(pin.debridService, 'rd');
      expect(pin.debridTorrentId, isEmpty);
      expect(pin.boundAt, 42);
      expect(pin.addonCatalogId, 'catalog');
      expect(pin.addonCatalogKey, 'catalog-configuration');
      expect(
        bind(row(type: StreamType.torrent), provider: 'torbox')!.debridService,
        'torbox',
      );
      expect(bind(row(type: StreamType.externalUrl)), isNull);
      expect(bind(row(type: StreamType.torrent, hash: '')), isNull);
      for (final provider in [
        SeriesSource.localService,
        SeriesSource.addonDirectService,
        SeriesSource.iptvDirectService,
      ]) {
        expect(bind(row(type: StreamType.torrent), provider: provider), isNull);
      }
    },
  );
}
