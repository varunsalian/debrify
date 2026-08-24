import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/iptv_hidden_categories_page.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/utils/platform_util.dart';

IptvChannel _ch(int i, {required String group, int? number}) => IptvChannel(
  channelNumber: number,
  name: 'Channel $i',
  url: 'http://h/live/u/p/$i.ts',
  group: group,
  duration: -1,
  contentType: 'live',
);

void main() {
  late Directory dir;
  const key = 'm3u|http://example/list.m3u';

  /// Three categories: Sports (0,3), News (1,4), Adult (2,5).
  void ingestSample() {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: key,
      channels: [
        for (var i = 0; i < 6; i++)
          _ch(i, group: ['Sports', 'News', 'Adult'][i % 3], number: i + 1),
      ],
      categories: const ['Sports', 'News', 'Adult'],
      numberingSourceKey: 'source-1',
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hidden_categories_test');
    IptvCatalogDb.debugDirectoryOverride = dir.path;
    await IptvCatalogDb.open();
    ingestSample();
  });

  tearDown(() async {
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    await dir.delete(recursive: true);
  });

  test('hiding a category drops its rows from counts, pages and groups', () {
    final before = IptvCatalogDb.snapshot(key)!;
    expect(before.count(), 6);
    expect(before.groups().length, 3);

    IptvCatalogDb.setGroupHidden(key, 'Adult', true);

    final after = IptvCatalogDb.snapshot(key)!;
    expect(after.count(), 4);
    expect(
      after.page(offset: 0, limit: 50).map((c) => c.group),
      isNot(contains('Adult')),
    );
    expect(after.groups().map((g) => g.name), ['Sports', 'News']);
    // The manager screen still has to see it.
    expect(
      after.groups(includeHidden: true).map((g) => g.name),
      containsAll(['Sports', 'News', 'Adult']),
    );
    expect(IptvCatalogDb.hiddenGroups(key), {'Adult'});
  });

  test('a hidden category is excluded from search and from its own filter', () {
    IptvCatalogDb.setGroupHidden(key, 'Adult', true);
    final snap = IptvCatalogDb.snapshot(key)!;
    // "channel" matches every row's name; only the visible ones come back.
    expect(snap.count(search: 'channel'), 4);
    // Explicitly asking for the hidden group yields nothing rather than
    // smuggling it back in.
    expect(snap.count(group: 'Adult'), 0);
  });

  test('position→index arithmetic stays consistent with the pages', () {
    IptvCatalogDb.setGroupHidden(key, 'Sports', true);
    final snap = IptvCatalogDb.snapshot(key)!;
    final rows = snap.pageEntries(offset: 0, limit: 50);
    expect(rows.length, 4);
    for (var i = 0; i < rows.length; i++) {
      // What the zap ladder does: turn a catalog position into a list index.
      expect(snap.count(beforePosition: rows[i].position), i);
    }
  });

  test('numeric tuning never lands on a hidden channel', () {
    // Read the numbers the catalog actually assigned rather than assuming
    // them — ingest owns numbering.
    final all = IptvCatalogDb.snapshot(key)!.page(offset: 0, limit: 50);
    final sportsNumber = all
        .firstWhere((c) => c.group == 'Sports')
        .channelNumber;
    final newsNumber = all.firstWhere((c) => c.group == 'News').channelNumber;
    expect(sportsNumber, isNotNull);
    expect(newsNumber, isNotNull);
    expect(
      IptvCatalogDb.snapshot(key)!.entryForChannelNumber(sportsNumber!),
      isNotNull,
    );

    IptvCatalogDb.setGroupHidden(key, 'Sports', true);
    final snap = IptvCatalogDb.snapshot(key)!;
    expect(snap.entryForChannelNumber(sportsNumber), isNull);
    expect(snap.positionOfChannelNumber(sportsNumber), isNull);
    // A number in a visible category still tunes.
    expect(snap.entryForChannelNumber(newsNumber!), isNotNull);
  });

  test('ungrouped channels are never hidden by a category rule', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: key,
      channels: [
        IptvChannel(
          name: 'Loose',
          url: 'http://h/loose.ts',
          duration: -1,
          contentType: 'live',
        ),
        _ch(9, group: 'Adult'),
      ],
    );
    IptvCatalogDb.setGroupHidden(key, 'Adult', true);
    final snap = IptvCatalogDb.snapshot(key)!;
    expect(snap.count(), 1);
    expect(snap.page(offset: 0, limit: 10).single.name, 'Loose');
  });

  test('hiding survives a refresh that writes a new generation', () {
    IptvCatalogDb.setGroupHidden(key, 'Adult', true);
    final firstGeneration = IptvCatalogDb.snapshot(key)!.generation;
    // Same catalog key, brand new rows and generation — a manual refresh.
    ingestSample();
    final snap = IptvCatalogDb.snapshot(key)!;
    expect(snap.generation, greaterThan(firstGeneration));
    expect(snap.count(), 4, reason: 'the rule is keyed by name, not by row');
  });

  test('unhiding and show-all restore the rows', () {
    IptvCatalogDb.setGroupHidden(key, 'Adult', true);
    IptvCatalogDb.setGroupHidden(key, 'News', true);
    expect(IptvCatalogDb.snapshot(key)!.count(), 2);

    IptvCatalogDb.setGroupHidden(key, 'News', false);
    expect(IptvCatalogDb.snapshot(key)!.count(), 4);

    IptvCatalogDb.showAllGroups(key);
    expect(IptvCatalogDb.snapshot(key)!.count(), 6);
    expect(IptvCatalogDb.hiddenGroups(key), isEmpty);
  });

  test('hide-all batches every named category into one durable update', () {
    IptvCatalogDb.hideGroups(key, ['Sports', 'News', 'Adult', '']);

    expect(IptvCatalogDb.hiddenGroups(key), {'Sports', 'News', 'Adult'});
    expect(IptvCatalogDb.snapshot(key)!.count(), 0);

    IptvCatalogDb.showAllGroups(key);
    expect(IptvCatalogDb.snapshot(key)!.count(), 6);
  });

  test('hidden sets are per catalog and countable in one query', () {
    const other = 'm3u|http://example/other.m3u';
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: other,
      channels: [_ch(1, group: 'Adult'), _ch(2, group: 'Sports')],
    );
    IptvCatalogDb.setGroupHidden(key, 'Adult', true);

    // Same category NAME in another provider is a different rule.
    expect(IptvCatalogDb.snapshot(other)!.count(), 2);
    expect(IptvCatalogDb.hiddenGroupCounts([key, other]), {key: 1});

    IptvCatalogDb.setGroupHidden(other, 'Adult', true);
    IptvCatalogDb.setGroupHidden(other, 'Sports', true);
    expect(IptvCatalogDb.hiddenGroupCounts([key, other]), {key: 1, other: 2});

    IptvCatalogDb.forgetHiddenGroups([other]);
    expect(IptvCatalogDb.hiddenGroupCounts([key, other]), {key: 1});
  });

  // The settings page clears hidden rules for the catalog keys an edit makes
  // UNREACHABLE (old keys minus new keys), rather than on "credentials
  // changed" — these are the two cases that distinction exists for.
  test('a password-only edit leaves the catalog keys — and rules — intact', () {
    IptvPlaylist xtream(String password) => IptvPlaylist(
      id: 'p1',
      name: 'Panel',
      url: '',
      serverUrl: 'http://panel:8080',
      username: 'user',
      password: password,
      addedAt: DateTime(2026),
    );
    Set<String> keys(IptvPlaylist p) => {
      for (final type in IptvCatalogKey.xtreamContentTypes)
        IptvCatalogKey.forPlaylist(p, type)!,
    };

    expect(keys(xtream('new')).difference(keys(xtream('old'))), isEmpty);

    final renamedAccount = IptvPlaylist(
      id: 'p1',
      name: 'Panel',
      url: '',
      serverUrl: 'http://panel:8080',
      username: 'other',
      password: 'old',
      addedAt: DateTime(2026),
    );
    expect(keys(xtream('old')).difference(keys(renamedAccount)), hasLength(3));
  });

  test('an empty category name is not storable as a rule', () {
    expect(IptvCatalogDb.setGroupHidden(key, '', true), isFalse);
    expect(IptvCatalogDb.hiddenGroups(key), isEmpty);
    expect(IptvCatalogDb.snapshot(key)!.count(), 6);
  });

  test('writes report success when saved and failure when the db is closed', () {
    expect(IptvCatalogDb.setGroupHidden(key, 'Adult', true), isTrue);
    expect(IptvCatalogDb.hideGroups(key, const ['News']), isTrue);
    expect(IptvCatalogDb.showAllGroups(key), isTrue);

    IptvCatalogDb.debugClose();
    expect(IptvCatalogDb.setGroupHidden(key, 'Adult', true), isFalse);
    expect(IptvCatalogDb.hideGroups(key, const ['News']), isFalse);
    expect(IptvCatalogDb.showAllGroups(key), isFalse);
  });

  testWidgets('TV DPAD reveals category rows past the initial viewport', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    await tester.binding.setSurfaceSize(const Size(1280, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final categories = List.generate(24, (i) => 'Category $i');
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: key,
      channels: [
        for (var i = 0; i < categories.length; i++)
          _ch(i, group: categories[i], number: i + 1),
      ],
      categories: categories,
      numberingSourceKey: 'source-1',
    );
    final playlist = IptvPlaylist(
      id: 'source-1',
      name: 'Example playlist',
      url: 'http://example/list.m3u',
      addedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(home: IptvHiddenCategoriesPage(playlist: playlist)),
    );
    // SettingsBackground has an intentionally continuous ambient animation,
    // while the catalog GROUP BY runs in a real worker isolate. Wait for the
    // query without waiting for the whole widget tree to become idle.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    final firstRow = find.byWidgetPredicate(
      (widget) =>
          widget is Focus &&
          widget.focusNode?.debugLabel == 'iptv-hidden-row-0',
    );
    final firstNode = tester.widget<Focus>(firstRow).focusNode!;
    firstNode.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Show all'), findsOneWidget);
    expect(find.text('Hide all'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'iptv-hidden-hide-all',
      reason: 'UP from the first row must reach Hide all on TV',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'iptv-hidden-row-0');

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final before = scrollable.position.pixels;
    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'iptv-hidden-row-10',
    );
    expect(
      scrollable.position.pixels,
      greaterThan(before),
      reason: 'moving focus below the fold must scroll the category list',
    );

    scrollable.position.jumpTo(0);
    await tester.pump();
    firstNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(
      IptvCatalogDb.hiddenGroups(key),
      categories.toSet(),
      reason: 'Hide all must apply every category, not just visible rows',
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'iptv-hidden-show-all',
      reason:
          'after hiding all, focus advances to the now-useful inverse action',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    expect(IptvCatalogDb.hiddenGroups(key), isEmpty);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'iptv-hidden-hide-all',
      reason: 'Show all must restore the opposite action as the DPAD anchor',
    );
  });
}
