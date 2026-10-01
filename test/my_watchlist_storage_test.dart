import 'dart:convert';

import 'package:debrify/services/storage/watchlist_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';

StremioMeta _title({
  required String id,
  String? imdbId,
  String type = 'movie',
  String name = 'A Movie',
  StremioAddon? addon,
}) => StremioMeta(
  id: id,
  imdbId: imdbId,
  type: type,
  name: name,
  poster: 'https://example.com/$id.jpg',
  background: 'https://example.com/$id-bg.jpg',
  year: '2026',
  sourceAddon: addon,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('stores full movie and series metadata newest first', () async {
    final addon = StremioAddon(
      id: 'catalog.addon',
      name: 'Catalog',
      manifestUrl: 'https://example.com/manifest.json',
      baseUrl: 'https://example.com',
    );
    final movie = _title(id: 'tt0000001', imdbId: 'tt0000001', addon: addon);
    final series = _title(
      id: 'tt0000002',
      imdbId: 'tt0000002',
      type: 'series',
      name: 'A Series',
      addon: addon,
    );

    await WatchlistStorage.setMyWatchlistItem(movie, true);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await WatchlistStorage.setMyWatchlistItem(series, true);

    final saved = await WatchlistStorage.getMyWatchlistItems();
    expect(saved.map((item) => item.name), ['A Series', 'A Movie']);
    expect(saved.first.poster, series.poster);
    expect(saved.first.sourceAddon?.id, addon.id);
    expect(await WatchlistStorage.isInMyWatchlist(movie), isTrue);
  });

  test('deduplicates the same IMDb title across addons', () async {
    final first = _title(id: 'addon-a:1', imdbId: 'tt1234567', name: 'Old');
    final second = _title(id: 'addon-b:9', imdbId: 'tt1234567', name: 'Fresh');

    await WatchlistStorage.setMyWatchlistItem(first, true);
    await WatchlistStorage.setMyWatchlistItem(second, true);

    final saved = await WatchlistStorage.getMyWatchlistItems();
    expect(saved, hasLength(1));
    expect(saved.single.name, 'Fresh');
  });

  test('namespaces non-IMDb ids by source addon', () async {
    final addonA = StremioAddon(
      id: 'addon.a',
      name: 'A',
      manifestUrl: '',
      baseUrl: '',
    );
    final addonB = StremioAddon(
      id: 'addon.b',
      name: 'B',
      manifestUrl: '',
      baseUrl: '',
    );
    final first = _title(id: 'local:1', name: 'First', addon: addonA);
    final second = _title(id: 'local:1', name: 'Second', addon: addonB);

    await WatchlistStorage.setMyWatchlistItem(first, true);
    await WatchlistStorage.setMyWatchlistItem(second, true);

    expect(await WatchlistStorage.getMyWatchlistItems(), hasLength(2));
    await WatchlistStorage.setMyWatchlistItem(first, false);
    final remaining = await WatchlistStorage.getMyWatchlistItems();
    expect(remaining.map((item) => item.name), ['Second']);
  });

  test('watchlist source normalization preserves a stored source', () {
    final stored = StremioAddon(
      id: 'stored.addon',
      name: 'Stored',
      manifestUrl: '',
      baseUrl: '',
    );
    final fallback = StremioAddon(
      id: 'fallback.addon',
      name: 'Fallback',
      manifestUrl: '',
      baseUrl: '',
    );
    final sourced = _title(id: 'local:1', addon: stored);
    final sourceLess = _title(id: 'local:2');

    expect(
      WatchlistStorage.withMyWatchlistSource(sourced, fallback).sourceAddon?.id,
      stored.id,
    );
    expect(
      WatchlistStorage.withMyWatchlistSource(sourceLess, fallback).sourceAddon?.id,
      fallback.id,
    );
  });

  test('source normalization keeps non-IMDb lookup and removal stable', () async {
    final fallback = StremioAddon(
      id: 'xtream-iptv',
      name: 'Xtream',
      manifestUrl: '',
      baseUrl: '',
    );
    final sourceLess = _title(
      id: 'xtream-series:playlist:77',
      type: 'series',
      name: 'Direct Series',
    );
    final identity = WatchlistStorage.withMyWatchlistSource(
      sourceLess,
      fallback,
    );

    await WatchlistStorage.setMyWatchlistItem(identity, true);
    expect(await WatchlistStorage.isInMyWatchlist(identity), isTrue);
    await WatchlistStorage.setMyWatchlistItem(identity, false);
    expect(await WatchlistStorage.isInMyWatchlist(identity), isFalse);
    expect(await WatchlistStorage.getMyWatchlistItems(), isEmpty);
  });

  test('canonicalizes an older un-namespaced fallback key', () async {
    final prefs = await SharedPreferences.getInstance();
    final addon = StremioAddon(
      id: 'addon.a',
      name: 'A',
      manifestUrl: '',
      baseUrl: '',
    );
    final item = _title(id: 'local:1', addon: addon);
    await prefs.setString(
      'my_watchlist_v1',
      jsonEncode([
        {'key': 'movie:local:1', 'addedAt': 42, 'item': item.toJson()},
      ]),
    );

    expect(await WatchlistStorage.isInMyWatchlist(item), isTrue);
    await WatchlistStorage.setMyWatchlistItem(item, false);
    expect(await WatchlistStorage.getMyWatchlistItems(), isEmpty);
  });

  test('rejects unsupported content types', () async {
    final channel = _title(id: 'channel:1', type: 'channel');

    expect(WatchlistStorage.supportsMyWatchlistItem(channel), isFalse);
    expect(await WatchlistStorage.isInMyWatchlist(channel), isFalse);
    await expectLater(
      WatchlistStorage.setMyWatchlistItem(channel, true),
      throwsArgumentError,
    );
    expect(await WatchlistStorage.getMyWatchlistItems(), isEmpty);
  });

  test('a malformed addedAt does not hide valid saved rows', () async {
    final prefs = await SharedPreferences.getInstance();
    final first = _title(id: 'tt1000001', imdbId: 'tt1000001', name: 'First');
    final second = _title(id: 'tt1000002', imdbId: 'tt1000002', name: 'Second');
    await prefs.setString(
      'my_watchlist_v1',
      jsonEncode([
        {
          'key': 'movie:tt1000001',
          'addedAt': 'not-a-timestamp',
          'item': first.toJson(),
        },
        {'key': 'movie:tt1000002', 'addedAt': 42, 'item': second.toJson()},
      ]),
    );

    final saved = await WatchlistStorage.getMyWatchlistItems();
    expect(saved.map((item) => item.name), ['Second', 'First']);
  });

  test('removes a title and clears the list', () async {
    final movie = _title(id: 'tt7654321', imdbId: 'tt7654321');
    await WatchlistStorage.setMyWatchlistItem(movie, true);
    await WatchlistStorage.setMyWatchlistItem(movie, false);

    expect(await WatchlistStorage.isInMyWatchlist(movie), isFalse);
    expect(await WatchlistStorage.getMyWatchlistItems(), isEmpty);
  });

  test('tvOS cap trims oldest rows and always keeps the newest save', () async {
    WatchlistStorage.debugMyWatchlistTvOsCapOverride = true;
    addTearDown(() => WatchlistStorage.debugMyWatchlistTvOsCapOverride = null);

    // ~5KB per row, so a handful of saves cross the 48KiB ceiling.
    final filler = 'x' * 5000;
    for (var i = 0; i < 15; i++) {
      final imdb = 'tt${i.toString().padLeft(7, '0')}';
      await WatchlistStorage.setMyWatchlistItem(
        _title(id: imdb, imdbId: imdb, name: 'Movie $i $filler'),
        true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    final prefs = await SharedPreferences.getInstance();
    final storedKey = prefs.getKeys().firstWhere(
      (key) => key.contains('my_watchlist_v1'),
    );
    final encoded = prefs.getString(storedKey)!;
    expect(
      utf8.encode(encoded).length,
      lessThanOrEqualTo(WatchlistStorage.myWatchlistTvOsCapBytes),
    );

    final saved = await WatchlistStorage.getMyWatchlistItems();
    expect(saved.length, lessThan(15), reason: 'the cap must have trimmed');
    expect(saved.first.name, startsWith('Movie 14 '));
    expect(
      saved.any((item) => item.name.startsWith('Movie 0 ')),
      isFalse,
      reason: 'the oldest row is the one dropped',
    );
  });

  test('re-saving the oldest title over the cap never evicts it', () async {
    WatchlistStorage.debugMyWatchlistTvOsCapOverride = true;
    addTearDown(() => WatchlistStorage.debugMyWatchlistTvOsCapOverride = null);

    final filler = 'x' * 5000;
    for (var i = 0; i < 15; i++) {
      final imdb = 'tt${i.toString().padLeft(7, '0')}';
      await WatchlistStorage.setMyWatchlistItem(
        _title(id: imdb, imdbId: imdb, name: 'Movie $i $filler'),
        true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    // Re-save the oldest survivor with bigger metadata, forcing a trim while
    // it holds the oldest addedAt (re-saves keep the original timestamp).
    final oldest = (await WatchlistStorage.getMyWatchlistItems()).last;
    final grown = _title(
      id: oldest.effectiveImdbId!,
      imdbId: oldest.effectiveImdbId,
      name: '${oldest.name} ${'y' * 8000}',
    );
    await WatchlistStorage.setMyWatchlistItem(grown, true);

    expect(await WatchlistStorage.isInMyWatchlist(grown), isTrue);
  });

  test('the cap never drops the sole remaining row', () async {
    WatchlistStorage.debugMyWatchlistTvOsCapOverride = true;
    addTearDown(() => WatchlistStorage.debugMyWatchlistTvOsCapOverride = null);

    final oversized = _title(
      id: 'tt7654321',
      imdbId: 'tt7654321',
      name: 'Huge ${'x' * (WatchlistStorage.myWatchlistTvOsCapBytes + 1024)}',
    );
    await WatchlistStorage.setMyWatchlistItem(oversized, true);
    expect(await WatchlistStorage.getMyWatchlistItems(), hasLength(1));
  });
}
