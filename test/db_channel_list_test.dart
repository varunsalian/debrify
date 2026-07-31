import 'dart:collection';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/widgets/iptv/db_channel_list.dart';

/// The paging facade's instance-stability contract: across the fresh facade
/// each filter/search recompute builds, a row that stays in the result set
/// must keep its SAME IptvChannel instance (stable ObjectKey → the grid
/// reuses the row's State instead of tearing it down and re-resolving EPG /
/// churning focus). Distinct catalog rows must never share an instance, even
/// when their url+name collide.
void main() {
  late Directory dir;

  IptvChannel ch(int i, {String? name, String? group, String? url}) =>
      IptvChannel(
        name: name ?? 'Channel $i',
        url: url ?? 'http://h/live/u/p/$i.ts',
        group: group,
        duration: -1,
        contentType: 'live',
        attributes: {'stream_id': '$i'},
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('db_channel_list');
    IptvCatalogDb.debugDirectoryOverride = dir.path;
    await IptvCatalogDb.open();
  });

  tearDown(() async {
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    await dir.delete(recursive: true);
  });

  CatalogSnapshot seed(List<IptvChannel> channels) {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: channels,
    );
    return IptvCatalogDb.snapshot('k')!;
  }

  test('a row surviving a filter recompute keeps its instance', () {
    final snap = seed([
      ch(0, name: 'Sky Sports F1', group: 'Sports'),
      ch(1, name: 'BBC News', group: 'News'),
      ch(2, name: 'Sky Cinema', group: 'Movies'),
    ]);
    final cache = LinkedHashMap<int, IptvChannel>();

    // "all" facade — fault the first row.
    final all = DbChannelList(snap, instanceCache: cache);
    final fromAll = all[0]; // Sky Sports F1 at position 0

    // A search recompute builds a brand-new facade (empty page cache) sharing
    // the same instance cache. "Sky Sports F1" still matches "sky".
    final searched = DbChannelList(snap, search: 'sky', instanceCache: cache);
    final fromSearch = searched[0];

    expect(identical(fromAll, fromSearch), isTrue,
        reason: 'same catalog row across recomputes → same instance');
  });

  test('without a shared cache, recomputes mint new instances', () {
    final snap = seed([ch(0, name: 'Sky Sports F1')]);
    final a = DbChannelList(snap); // no cache
    final b = DbChannelList(snap, search: 'sky');
    expect(identical(a[0], b[0]), isFalse);
  });

  test('duplicate url+name rows never share an instance', () {
    // Two distinct catalog rows with identical url AND name — legal in the
    // wild. They sit at different positions, so the position-keyed cache
    // keeps them distinct (a shared instance would collapse their ObjectKeys
    // and scramble focus).
    final snap = seed([
      ch(0, name: 'Dup', url: 'http://h/live/u/p/same.ts'),
      ch(1, name: 'Dup', url: 'http://h/live/u/p/same.ts'),
    ]);
    final cache = LinkedHashMap<int, IptvChannel>();
    final list = DbChannelList(snap, instanceCache: cache);
    expect(identical(list[0], list[1]), isFalse);
  });

  test('the cache is bounded and evicts the eldest', () {
    final snap = seed([for (var i = 0; i < 1000; i++) ch(i)]);
    final cache = LinkedHashMap<int, IptvChannel>();
    final list = DbChannelList(snap, instanceCache: cache);
    // Walk far more rows than the cap.
    for (var i = 0; i < 1000; i++) {
      list[i];
    }
    expect(cache.length, lessThanOrEqualTo(DbChannelList.maxCachedInstances));
  });

  test('length and contents still reflect the filter', () {
    final snap = seed([
      ch(0, name: 'Sky Sports'),
      ch(1, name: 'BBC'),
      ch(2, name: 'Sky News'),
    ]);
    final cache = LinkedHashMap<int, IptvChannel>();
    final searched = DbChannelList(snap, search: 'sky', instanceCache: cache);
    expect(searched.length, 2);
    expect(searched.map((c) => c.name), ['Sky Sports', 'Sky News']);
  });
}
