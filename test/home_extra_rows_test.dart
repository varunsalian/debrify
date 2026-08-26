import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/home_list_rows.dart';
import 'package:debrify/services/mdblist/mdblist_list_source.dart';
import 'package:debrify/services/simkl/simkl_list_source.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/trakt/trakt_list_source.dart';

StremioMeta _meta(String id) =>
    StremioMeta(id: id, type: 'movie', name: 'Title $id');

({List<StremioMeta> items, bool failed}) _ok(String id) =>
    (items: [_meta(id)], failed: false);

const _empty = (items: <StremioMeta>[], failed: false);
const _failed = (items: <StremioMeta>[], failed: true);

TraktListChoice _userList(int id, String name, {bool liked = false}) =>
    TraktListChoice.userList({
      'name': name,
      'ids': {'trakt': id, 'slug': 'slug-$id'},
    }, liked: liked);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageService home extra rows', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('round-trips rows and clears the key when empty', () async {
      expect(await StorageService.getHomeExtraRows(), isEmpty);

      await StorageService.setHomeExtraRows(const [
        (id: 'traktlist:watchlist', title: ''),
        (id: 'iptvlist:list_1', title: 'Sports'),
      ]);
      final rows = await StorageService.getHomeExtraRows();
      expect(rows, hasLength(2));
      expect(rows[0].id, 'traktlist:watchlist');
      expect(rows[1], (id: 'iptvlist:list_1', title: 'Sports'));

      await StorageService.setHomeExtraRows(const []);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('home_extra_rows_v1'), isNull);
    });

    test('tolerates corrupt json and malformed entries', () async {
      SharedPreferences.setMockInitialValues({
        'home_extra_rows_v1': 'not-json{',
      });
      expect(await StorageService.getHomeExtraRows(), isEmpty);

      SharedPreferences.setMockInitialValues({
        'home_extra_rows_v1': jsonEncode([
          {'id': 'simkllist:trending', 'title': 'Trending'},
          {'title': 'no id'},
          'bare string',
          {'id': '', 'title': 'empty id'},
          {'id': 'simkllist:trending', 'title': 'duplicate'},
          {'id': 'traktlist:popular', 'title': 42},
        ]),
      });
      final rows = await StorageService.getHomeExtraRows();
      expect(rows, hasLength(2));
      expect(rows[0], (id: 'simkllist:trending', title: 'Trending'));
      // Non-string title degrades to '' rather than dropping the row.
      expect(rows[1], (id: 'traktlist:popular', title: ''));
    });
  });

  group('HomeExtraRowIds', () {
    test('id grammar is stable', () {
      expect(
        HomeExtraRowIds.traktBuiltin(TraktSeeAllList.watchlist),
        'traktlist:watchlist',
      );
      expect(
        HomeExtraRowIds.simkl(SimklSeeAllList.planToWatch),
        'simkllist:planToWatch',
      );
      expect(HomeExtraRowIds.iptvList('abc'), 'iptvlist:abc');
      expect(
        HomeExtraRowIds.traktUserList(_userList(7, 'Mine')),
        'traktlist:custom:7',
      );
      expect(
        HomeExtraRowIds.traktUserList(_userList(9, 'Theirs', liked: true)),
        'traktlist:liked:9',
      );
      expect(HomeExtraRowIds.isTracker('traktlist:watchlist'), isTrue);
      expect(HomeExtraRowIds.isTracker('simkllist:trending'), isTrue);
      expect(HomeExtraRowIds.isTracker('mdblistlist:mine:7'), isTrue);
      expect(HomeExtraRowIds.isTracker('iptvlist:x'), isFalse);
      expect(HomeExtraRowIds.iptvListId('iptvlist:x'), 'x');
      expect(HomeExtraRowIds.iptvListId('traktlist:watchlist'), isNull);
    });
  });

  group('HomeListRowsService.resolve', () {
    test('MDBList refreshes only directories used by enabled rows', () async {
      var mineCalls = 0;
      var likedCalls = 0;
      var topCalls = 0;
      const liked = MdblistListChoice(id: 2, name: 'Liked', liked: true);
      final service = HomeListRowsService(
        traktLoad: (_) async => _empty,
        traktUserLists: () async => const [],
        simklLoad: (_) async => _empty,
        mdblistMine: () async {
          mineCalls++;
          return const [];
        },
        mdblistLiked: () async {
          likedCalls++;
          return const [liked];
        },
        mdblistTop: () async {
          topCalls++;
          return const [];
        },
        mdblistLoad: (_) async =>
            (items: [_meta('liked')], failed: false, complete: true),
      );

      final rows = await service.resolve(const [
        (id: 'mdblistlist:liked:2', title: 'Saved title'),
      ]);

      expect(rows.single.title, 'Saved title');
      expect((mineCalls, likedCalls, topCalls), (0, 1, 0));
      expect(rows.single.mdblistList?.liked, isTrue);
    });

    test(
      'MDBList rows retain group order and require a complete item walk',
      () async {
        const mine = MdblistListChoice(id: 1, name: 'Mine');
        const liked = MdblistListChoice(id: 2, name: 'Liked');
        const top = MdblistListChoice(id: 3, name: 'Top');
        final service = HomeListRowsService(
          traktLoad: (_) async => _empty,
          traktUserLists: () async => const [],
          simklLoad: (_) async => _empty,
          mdblistMine: () async => const [mine],
          mdblistLiked: () async => const [liked],
          mdblistTop: () async => const [top],
          mdblistLoad: (choice) async => (
            items: [_meta('${choice.id}')],
            failed: choice.id == 2,
            complete: choice.id != 2,
          ),
        );

        final rows = await service.resolve(const [
          (id: 'mdblistlist:top:3', title: ''),
          (id: 'mdblistlist:liked:2', title: ''),
          (id: 'mdblistlist:mine:1', title: ''),
        ]);

        expect(rows.map((row) => row.title), ['Mine', 'Top']);
        expect(rows.every((row) => row.isMdblist), isTrue);
      },
    );

    test('returns immediately when no tracker ids are enabled', () async {
      var loaderCalls = 0;
      final service = HomeListRowsService(
        traktLoad: (_) async {
          loaderCalls++;
          return _empty;
        },
        traktUserLists: () async {
          loaderCalls++;
          return const [];
        },
        simklLoad: (_) async {
          loaderCalls++;
          return _empty;
        },
      );
      final rows = await service.resolve(const [
        (id: 'iptvlist:abc', title: 'Sports'),
      ]);
      expect(rows, isEmpty);
      expect(loaderCalls, 0);
    });

    test(
      'canonical order regardless of stored order; empty rows drop',
      () async {
        final service = HomeListRowsService(
          traktLoad: (c) async =>
              c.builtin == TraktSeeAllList.popular ? _empty : _ok(c.label),
          traktUserLists: () async => const [],
          simklLoad: (l) async => _ok(l.label),
        );
        final rows = await service.resolve(const [
          (id: 'simkllist:trending', title: ''),
          (id: 'traktlist:popular', title: ''),
          (id: 'traktlist:trending', title: ''),
          (id: 'traktlist:watchlist', title: ''),
        ]);
        // Trakt built-ins in enum order (watchlist before trending), popular
        // dropped (empty), Simkl after every Trakt row.
        expect(rows.map((s) => s.title).toList(), [
          'Watchlist',
          'Trending',
          'Trending',
        ]);
        expect(rows[0].isTrakt, isTrue);
        expect(rows[1].traktChoice?.builtin, TraktSeeAllList.trending);
        expect(rows[2].simklList, SimklSeeAllList.trending);
        expect(rows.every((s) => s.exhausted), isTrue);
      },
    );

    test('one provider failing does not sink the other', () async {
      final service = HomeListRowsService(
        traktLoad: (_) async => throw Exception('trakt down'),
        traktUserLists: () async => throw Exception('trakt down'),
        simklLoad: (l) async => _ok(l.label),
      );
      final rows = await service.resolve(const [
        (id: 'traktlist:watchlist', title: ''),
        (id: 'traktlist:custom:7', title: 'Mine'),
        (id: 'simkllist:topRated', title: ''),
      ]);
      expect(rows.map((s) => s.title).toList(), ['Top Rated']);
    });

    test('failed-with-no-items drops the row; partial results kept', () async {
      final service = HomeListRowsService(
        traktLoad: (c) async => c.builtin == TraktSeeAllList.history
            ? _failed
            : (items: [_meta('a')], failed: true),
        traktUserLists: () async => const [],
        simklLoad: (_) async => _empty,
      );
      final rows = await service.resolve(const [
        (id: 'traktlist:history', title: ''),
        (id: 'traktlist:collection', title: ''),
      ]);
      expect(rows.map((s) => s.rowId).toList(), ['traktlist:collection']);
    });

    test('custom/liked lists resolve through the user-lists fetch', () async {
      final mine = _userList(7, 'Mine');
      final theirs = _userList(9, 'Theirs', liked: true);
      final service = HomeListRowsService(
        traktLoad: (c) async =>
            c.isBuiltin ? _ok(c.label) : _ok('user-${c.userListId}'),
        traktUserLists: () async => [mine, theirs],
        simklLoad: (_) async => _empty,
      );
      final rows = await service.resolve(const [
        (id: 'traktlist:liked:9', title: 'Stored Liked Title'),
        (id: 'traktlist:custom:7', title: ''),
        // Vanished upstream — must drop silently.
        (id: 'traktlist:custom:404', title: 'Gone'),
        (id: 'traktlist:anticipated', title: ''),
      ]);
      expect(rows.map((s) => s.title).toList(), [
        'Anticipated', // built-ins first
        'Mine', // stored title empty → account label
        'Stored Liked Title', // stored title wins
      ]);
      expect(rows[1].traktChoice?.userListId, '7');
      expect(rows[2].traktChoice?.liked, isTrue);
    });

    test('deadline keeps completed rows and drops stragglers', () async {
      final never = Completer<({List<StremioMeta> items, bool failed})>();
      final service = HomeListRowsService(
        traktLoad: (c) => c.builtin == TraktSeeAllList.watchlist
            ? Future.value(_ok('fast'))
            : never.future,
        traktUserLists: () async => const [],
        simklLoad: (l) async => _ok(l.label),
      );
      final rows = await service.resolve(const [
        (id: 'traktlist:watchlist', title: ''),
        (id: 'traktlist:trending', title: ''),
        (id: 'simkllist:ratings', title: ''),
      ], deadline: const Duration(milliseconds: 200));
      expect(rows.map((s) => s.rowId).toList(), [
        'traktlist:watchlist',
        'simkllist:ratings',
      ]);
    });

    test('caps concurrent fetches per provider at 3', () async {
      var active = 0;
      var peak = 0;
      final service = HomeListRowsService(
        traktLoad: (c) async {
          active++;
          peak = peak > active ? peak : active;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active--;
          return _ok(c.label);
        },
        traktUserLists: () async => const [],
        simklLoad: (_) async => _empty,
      );
      final rows = await service.resolve([
        for (final l in TraktSeeAllList.values)
          if (l != TraktSeeAllList.continueWatching)
            (id: HomeExtraRowIds.traktBuiltin(l), title: ''),
      ]);
      expect(rows, hasLength(8));
      expect(peak, lessThanOrEqualTo(3));
    });
  });
}
