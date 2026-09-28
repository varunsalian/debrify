import 'package:debrify/features/home/presentation/home_detail_menus.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HomeDetailMenus create({
    String? id = 'tt123',
    String type = 'series',
    bool local = false,
    bool trakt = false,
    bool mdblist = false,
  }) => HomeDetailMenus(
    type: type,
    identity: id,
    removalColor: Colors.purple,
    inLocalContinueWatching: local,
    inTraktContinueWatching: trakt,
    inMdblistContinueWatching: mdblist,
    hasBoundSource: () => false,
    traktAuthenticated: () => true,
    simklAuthenticated: () => true,
    mdblistAuthenticated: () => true,
    hasSimklPause: () => false,
  );
  test(
    'local and Trakt removals retain order, distinction and opening theme',
    () {
      final menus = create(local: true, trakt: true);
      final tail = menus.initialTrakt.reversed
          .take(2)
          .toList()
          .reversed
          .toList();
      expect(tail.map((o) => o.action), [
        TraktItemMenuAction.removeFromPlayback,
        TraktItemMenuAction.removeFromTraktPlayback,
      ]);
      expect(tail.map((o) => o.isTrakt), [false, true]);
      expect(tail.map((o) => o.color), [Colors.purple, Colors.purple]);
      expect(tail.map((o) => o.label), [
        'Remove from Continue Watching',
        'Remove from Trakt Continue Watching',
      ]);
      expect(tail.map((o) => o.caption), ['Remove', 'Remove']);
    },
  );

  for (final id in <String?>[
    null,
    const CustomSeriesIdentity('addon', 'catalog').id,
    'tmdb:123',
    'tt123',
  ]) {
    test('independent tracker identity gates preserve app actions for $id', () {
      final menus = create(id: id);
      expect(menus.initialTrakt.any((o) => o.isTrakt), id == 'tt123');
      expect(menus.initialMdblist.isNotEmpty, id == 'tt123');
      expect(menus.initialSimkl.isNotEmpty, id == 'tt123' || id == 'tmdb:123');
      expect(
        menus.initialTrakt.map((o) => o.action),
        containsAll([
          TraktItemMenuAction.selectSource,
          TraktItemMenuAction.addToStremioTv,
          TraktItemMenuAction.playRandomEpisode,
          TraktItemMenuAction.searchPacks,
        ]),
      );
    });
  }

  test('movie source labels and series-only actions stay distinct', () {
    final movie = create(type: 'movie');
    expect(
      movie.initialTrakt.map((o) => o.action),
      isNot(contains(TraktItemMenuAction.playRandomEpisode)),
    );
    expect(
      movie.initialTrakt.map((o) => o.action),
      isNot(contains(TraktItemMenuAction.searchPacks)),
    );
    expect(
      movie.initialSimkl.map((o) => o.action),
      isNot(contains(SimklItemMenuAction.moveToOnHold)),
    );
  });

  test(
    'opening snapshots remain stable while live status, binding and auth change',
    () {
      var authenticated = true, bound = false, paused = false;
      final menus = HomeDetailMenus(
        type: 'series',
        identity: 'tt123',
        removalColor: Colors.red,
        inLocalContinueWatching: false,
        inTraktContinueWatching: false,
        inMdblistContinueWatching: true,
        hasBoundSource: () => bound,
        traktAuthenticated: () => authenticated,
        simklAuthenticated: () => authenticated,
        mdblistAuthenticated: () => authenticated,
        hasSimklPause: () => paused,
      );
      expect(menus.initialTrakt.first.label, 'Select Source');
      expect(
        menus.initialSimkl.map((o) => o.action),
        isNot(contains(SimklItemMenuAction.removeFromContinueWatching)),
      );
      bound = true;
      paused = true;
      final trakt = menus.trakt(
        const TraktTitleStatus(
          inWatchlist: true,
          inCollection: true,
          rating: 8,
        ),
      );
      expect(trakt.first.label, 'Edit Sources');
      expect(
        trakt.map((o) => o.action),
        containsAll([
          TraktItemMenuAction.removeFromWatchlist,
          TraktItemMenuAction.removeFromCollection,
          TraktItemMenuAction.removeRating,
        ]),
      );
      final simkl = menus.simkl(
        const SimklTitleStatus(currentStatus: 'hold', rating: 7),
      );
      expect(
        simkl.map((o) => o.action),
        containsAll([
          SimklItemMenuAction.removeFromList,
          SimklItemMenuAction.removeRating,
          SimklItemMenuAction.removeFromContinueWatching,
        ]),
      );
      expect(
        simkl.map((o) => o.action),
        isNot(contains(SimklItemMenuAction.moveToOnHold)),
      );
      final mdblist = menus.mdblist(
        const MdblistTitleStatus(
          id: 'tt123',
          watched: true,
          collected: true,
          rating: 6,
          inWatchlist: true,
        ),
      );
      expect(
        mdblist.map((o) => o.action),
        containsAll([
          MdblistItemMenuAction.removeFromWatchlist,
          MdblistItemMenuAction.removeFromCollection,
          MdblistItemMenuAction.removeRating,
        ]),
      );
      authenticated = false;
      expect(menus.trakt(null).where((o) => o.isTrakt), isEmpty);
      expect(menus.simkl(null), isEmpty);
      expect(menus.mdblist(null), isEmpty);
      expect(menus.initialTrakt.first.label, 'Select Source');
      expect(
        menus.initialTrakt.map((o) => o.action),
        contains(TraktItemMenuAction.addToWatchlist),
      );
      expect(menus.initialSimkl, isNotEmpty);
      expect(menus.initialMdblist, isNotEmpty);
    },
  );
}
