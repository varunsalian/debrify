import 'package:debrify/screens/playlist_content_view_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/playlist_preferences_storage.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/playlist_content_fixture.dart';

void main() {
  testWidgets(
    'Raw alias folder path identity sort numeric order and persisted navigation',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t);
      final path = f.member('folderPath');
      expect(identical(f.member('currentViewNodes'), f.root.children), isTrue);
      f.member('navigateIntoFolder')(f.root.children.single);
      expect(identical(f.member('folderPath'), path), isTrue);
      expect(path, ['Pack']);
      expect(
        identical(
          f.member('currentViewNodes'),
          f.root.children.single.children,
        ),
        isTrue,
      );
      f.member('applyViewMode')(FolderViewMode.sortedAZ);
      await t.pump();
      expect(f.visible.map((n) => n.name), [
        '2. Two.mkv',
        '10. Ten.mkv',
        'readme.txt',
      ]);
      final ordered = f.root.getAllFiles();
      final identity = ordered;
      f.member('applySortedPlaylistOrder')(ordered);
      expect(identical(ordered, identity), isTrue);
      expect(ordered.map((n) => n.fileId), [2, 9, 5]);
      expect(
        await t.runAsync(
          () => PlaylistPreferencesStorage.getPlaylistItemViewMode(f.item),
        ),
        'sortedAZ',
      );
      await t.runAsync(
        () =>
            PlaylistPreferencesStorage.savePlaylistItemViewMode(f.item, 'raw'),
      );
      f.member('navigateUp')();
      await t.pump();
      expect(identical(f.member('folderPath'), path), isTrue);
      expect(path, isEmpty);
      expect(
        await t.runAsync(
          () => PlaylistPreferencesStorage.getPlaylistItemViewMode(f.item),
        ),
        'sortedAZ',
      );
      await t.runAsync(
        () =>
            PlaylistPreferencesStorage.savePlaylistItemViewMode(f.item, 'raw'),
      );
      f.member('navigateIntoFolder')(f.root.children.single);
      await t.pump();
      expect(path, ['Pack']);
      expect(
        await t.runAsync(
          () => PlaylistPreferencesStorage.getPlaylistItemViewMode(f.item),
        ),
        'sortedAZ',
      );
      f.member('navigateUp')();
      await t.pump();
      f.member('applyViewMode')(FolderViewMode.raw);
      await t.pump();
      expect(identical(f.member('currentViewNodes'), f.root.children), isTrue);
      expect(
        await t.runAsync(
          () => PlaylistPreferencesStorage.getPlaylistItemViewMode(f.item),
        ),
        'raw',
      );
    }),
  );
  testWidgets(
    'missing folder resets path root and Series Arrange closes search',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t);
      f.member('toggleSearch')();
      f.member('performSearch')('Two');
      expect(f.member('isSearchActive'), isTrue);
      final results = f.member('searchResults') as List;
      expect(results, hasLength(1));
      (f.member('folderPath') as List).add('missing');
      f.member('applyViewMode')(FolderViewMode.raw);
      expect(f.member('folderPath'), isEmpty);
      expect(identical(f.member('currentViewNodes'), f.root.children), isTrue);
      f.member('applyViewMode')(FolderViewMode.seriesArrange);
      expect(f.member('isSearchActive'), isFalse);
      expect(results, isEmpty);
      await t.pump();
    }),
  );
  testWidgets(
    'back priority search folder false sentinel registration identity',
    (t) => playlistContentCase(t, (f) async {
      var below = 0, above = 0;
      bool lower() {
        below++;
        return true;
      }

      bool upper() {
        above++;
        return true;
      }

      MainPageBridge.pushRouteBackHandler(lower);
      try {
        await f.mount(t, pushed: true);
        f.member('navigateIntoFolder')(f.root.children.single);
        f.member('toggleSearch')();
        expect(f.member('handleBackNavigation')(), isTrue);
        expect(f.member('isSearchActive'), isFalse);
        expect(f.member('folderPath'), ['Pack']);
        expect(f.member('handleBackNavigation')(), isTrue);
        expect(f.member('folderPath'), isEmpty);
        expect(f.member('handleBackNavigation')(), isFalse);
        final handler = f.member('handleBackNavigation') as bool Function();
        MainPageBridge.pushRouteBackHandler(upper);
        await t.pumpWidget(const SizedBox.shrink());
        expect(MainPageBridge.handleBackNavigation(), isTrue);
        expect(above, 1);
        MainPageBridge.popRouteBackHandler(upper);
        // The original bridge deliberately pops only the last matching handler;
        // disposal with a sentinel above leaves the screen handler below it.
        MainPageBridge.popRouteBackHandler(handler);
        expect(MainPageBridge.handleBackNavigation(), isTrue);
        expect(below, 1);
      } finally {
        MainPageBridge.popRouteBackHandler(upper);
        MainPageBridge.popRouteBackHandler(lower);
      }
    }),
  );
  testWidgets(
    'normal dispose removes own back handler and leaves sentinel',
    (t) => playlistContentCase(t, (f) async {
      var calls = 0;
      bool sentinel() {
        calls++;
        return true;
      }

      MainPageBridge.pushRouteBackHandler(sentinel);
      try {
        await f.mount(t);
        await t.pumpWidget(const SizedBox.shrink());
        expect(MainPageBridge.handleBackNavigation(), isTrue);
        expect(calls, 1);
      } finally {
        MainPageBridge.popRouteBackHandler(sentinel);
      }
    }),
  );
  testWidgets(
    'AppBar back navigates folder then pops at root',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t, pushed: true);
      f.member('navigateIntoFolder')(f.root.children.single);
      await t.pump();
      await t.tap(find.byIcon(Icons.arrow_back));
      await t.pump();
      expect(f.member('folderPath'), isEmpty);
      expect(f.key.currentState, isNotNull);
      await t.tap(find.byIcon(Icons.arrow_back));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await t.pump();
      expect(f.key.currentState, isNull);
      expect(f.observer.popped.whereType<MaterialPageRoute>(), hasLength(1));
    }),
  );
  testWidgets(
    'independent routes have fresh map list controller and focus owners',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t);
      final old = f.access;
      final secondKey = GlobalKey<State<PlaylistContentViewScreen>>();
      f.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              PlaylistContentViewScreen(key: secondKey, playlistItem: f.item),
        ),
      );
      await t.pump();
      await f.until(
        t,
        () =>
            secondKey.currentState != null &&
            playlistContentTestAccess(
                  secondKey.currentState!,
                )['currentViewNodes'] !=
                null,
      );
      final second = playlistContentTestAccess(secondKey.currentState!);
      for (final field in [
        'folderPath',
        'fileProgressCache',
        'searchResults',
        'searchController',
        'viewModeDropdownFocusNode',
        'episodeListScrollController',
      ]) {
        expect(identical(old[field], second[field]), isFalse, reason: field);
      }
      f.navigatorKey.currentState!.pop();
      await t.pump(const Duration(milliseconds: 600));
      expect(f.key.currentState, isNotNull);
    }),
  );
}
