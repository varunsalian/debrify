import 'dart:io';

import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:debrify/services/storage/playlist_preferences_storage.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/playlist_content_fixture.dart';
import 'playlist_content_progress_test.dart' show seedSeries;

const captureLinux = bool.fromEnvironment(
  'PLAYLIST_CONTENT_CAPTURE_ORIGINAL_LINUX',
);
const captureMac = bool.fromEnvironment(
  'PLAYLIST_CONTENT_CAPTURE_ORIGINAL_MACOS',
);
const requireLinux = bool.fromEnvironment(
  'PLAYLIST_CONTENT_REQUIRE_ORIGINAL_LINUX',
);
Future<void> enterOtt(WidgetTester t, PlaylistContentFixture f) async {
  f.member('applyViewMode')(FolderViewMode.seriesArrange);
  await t.pump();
  await f.until(
    t,
    () => PaintingBinding.instance.imageCache.pendingImageCount == 0,
  );
}

Focus episodeFocus(WidgetTester t) => t
    .widgetList<Focus>(find.byType(Focus))
    .firstWhere(
      (w) =>
          w.onKeyEvent != null && w.onFocusChange != null && w.child is Builder,
    );
void main() {
  testWidgets(
    'recursive video-only search reassign clear close paths and arrows',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t);
      final before = f.member('searchResults');
      await t.tap(find.byTooltip('Search files'));
      await t.pump();
      await t.enterText(find.byType(TextField), 't');
      await t.pump();
      final results = f.member('searchResults') as List;
      expect(identical(results, before), isFalse);
      expect(results.map((dynamic r) => r.node.name), [
        '10. Ten.mkv',
        '2. Two.mkv',
      ]);
      expect(results.map((dynamic r) => r.path), ['Pack', 'Pack']);
      final field = t.widget<TvTextField>(find.byType(TvTextField));
      field.onRightArrow!();
      await t.pump();
      expect((f.member('searchClearFocusNode') as FocusNode).hasFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect((f.member('searchFocusNode') as FocusNode).hasFocus, isTrue);
      field.onUpArrow!();
      await t.pump();
      expect((f.member('searchFocusNode') as FocusNode).hasFocus, isFalse);
      (f.member('searchClearFocusNode') as FocusNode).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pump();
      expect(results, isEmpty);
      expect(f.member('searchController').text, isEmpty);
      expect(find.text('Type to search all files'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'readme');
      await t.pump();
      expect(f.member('searchResults'), isEmpty);
      expect(find.text('No files found'), findsOneWidget);
      await t.tap(find.byTooltip('Close search'));
      await t.pump();
      expect(f.member('isSearchActive'), isFalse);
    }),
  );
  testWidgets(
    'nonseries auto-switch timer replaced every build deadline and persisted mode',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t);
      await enterOtt(t, f);
      final first = f.member('ottViewAutoSwitchTimer');
      expect(first.isActive, isTrue);
      await t.pump(const Duration(seconds: 1));
      f.member('setAndroidTv')(false);
      await t.pump();
      final replacement = f.member('ottViewAutoSwitchTimer');
      expect(identical(first, replacement), isFalse);
      expect(first.isActive, isFalse);
      await t.pump(const Duration(milliseconds: 1999));
      expect(f.member('currentViewMode'), FolderViewMode.seriesArrange);
      await t.pump(const Duration(milliseconds: 1));
      expect(f.member('currentViewMode'), FolderViewMode.sortedAZ);
      expect(
        await t.runAsync(
          () => PlaylistPreferencesStorage.getPlaylistItemViewMode(f.item),
        ),
        'sortedAZ',
      );
      await enterOtt(t, f);
      final last = f.member('ottViewAutoSwitchTimer');
      await t.pumpWidget(const SizedBox.shrink());
      expect(last.isActive, isFalse);
      await t.pump(const Duration(seconds: 3));
    }),
  );
  for (final width in [500.0, 1000.0]) {
    for (final tv in [false, true]) {
      testWidgets(
        'watched button remains live width=$width TV=$tv mark unmark local persistence',
        (t) => playlistContentCase(t, (f) async {
          seedSeries(f);
          await f.mount(t, width: width);
          await enterOtt(t, f);
          f.member('setAndroidTv')(tv);
          await t.pump();
          final outer = t
              .widgetList<InkWell>(
                find.descendant(
                  of: find.byType(Card),
                  matching: find.byType(InkWell),
                ),
              )
              .where((w) => w.child is Padding)
              .toList();
          expect(outer, hasLength(4));
          expect(outer.first.onTap == null, tv);
          expect(outer.first.onLongPress == null, tv);
          await t.tap(find.byIcon(Icons.circle_outlined).first);
          await f.until(t, () => f.progress['1_1']?['durationMs'] == 1);
          expect(
            await t.runAsync(
              () => EpisodeProgressStorage.isEpisodeFinished(
                seriesTitle: f.series.seriesTitle!,
                season: 1,
                episode: 1,
              ),
            ),
            isTrue,
          );
          expect(f.progress['1_1']?['positionMs'], 0);
          expect(find.text('Episode marked as watched'), findsOneWidget);
          expect(
            t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
            const Color(0xFF4CAF50),
          );
          await t.pump(const Duration(seconds: 3));
          await t.pump(const Duration(milliseconds: 300));
          await t.pump();
          await t.tap(find.byIcon(Icons.check));
          await f.until(t, () => !f.progress.containsKey('1_1'));
          expect(
            await t.runAsync(
              () => EpisodeProgressStorage.isEpisodeFinished(
                seriesTitle: f.series.seriesTitle!,
                season: 1,
                episode: 1,
              ),
            ),
            isFalse,
          );
          await f.until(
            t,
            () =>
                find.text('Episode marked as unwatched').evaluate().isNotEmpty,
          );
          expect(find.text('Episode marked as unwatched'), findsOneWidget);
          expect(
            t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
            const Color(0xFF6366F1),
          );
          expect(
            f.requests.where(
              (r) =>
                  r.url.host.contains('trakt') || r.url.host.contains('simkl'),
            ),
            isEmpty,
          );
        }),
      );
    }
  }
  testWidgets(
    'D-pad 800 ms hold repeat ignored 300 ms suppression and blur cancellation',
    (t) => playlistContentCase(t, (f) async {
      seedSeries(f);
      await f.mount(t);
      await enterOtt(t, f);
      f.member('setAndroidTv')(true);
      await t.pump();
      final focus = episodeFocus(t);
      final node = Focus.of(t.element(find.byWidget(focus.child)));
      node.requestFocus();
      await t.pump();
      expect(find.text('Hold to mark watched'), findsOneWidget);
      await t.sendKeyDownEvent(LogicalKeyboardKey.select);
      final timer = f.member('episodeLongPressTimer');
      await t.pump(const Duration(milliseconds: 400));
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      expect(identical(f.member('episodeLongPressTimer'), timer), isTrue);
      await t.pump(const Duration(milliseconds: 399));
      expect(f.member('episodeLongPressTriggered'), isFalse);
      await t.pump(const Duration(milliseconds: 1));
      expect(f.member('episodeLongPressTriggered'), isTrue);
      await f.until(t, () => f.progress['1_1']?['durationMs'] == 1);
      expect(find.text('Hold to unmark'), findsOneWidget);
      await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      final probe = PlaylistContentProbe(f)..install();
      try {
        await t.sendKeyEvent(LogicalKeyboardKey.select);
        await t.pump();
        expect(probe.calls, 0);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 301)),
        );
        await t.pump();
        node.requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.select);
        await f.until(t, () => probe.calls == 2);
        await t.pump(const Duration(milliseconds: 600));
        await t.pump();
        node.requestFocus();
        await t.pump();
        await t.sendKeyDownEvent(LogicalKeyboardKey.select);
        final pending = f.member('episodeLongPressTimer');
        (f.member('viewModeDropdownFocusNode') as FocusNode).requestFocus();
        await t.pump();
        expect(pending.isActive, isFalse);
        expect(f.member('episodeKeyDownReceived'), isFalse);
        await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      } finally {
        probe.remove();
      }
    }),
  );
  testWidgets(
    'non-TV outer long press toggles without launching',
    (t) => playlistContentCase(t, (f) async {
      seedSeries(f);
      await f.mount(t);
      await enterOtt(t, f);
      final outer = t
          .widgetList<InkWell>(find.byType(InkWell))
          .firstWhere((w) => w.onLongPress != null);
      outer.onLongPress!();
      await f.until(t, () => f.progress['1_1']?['durationMs'] == 1);
      expect(find.text('Episode marked as watched'), findsOneWidget);
    }),
  );
  for (final scene in ['raw', 'search', 'ott_mobile', 'ott_desktop', 'error']) {
    testWidgets(
      'reachable pixel golden $scene',
      tags: ['golden'],
      (t) => playlistContentCase(t, (f) async {
        if (scene.startsWith('ott')) {
          seedSeries(f);
        }
        if (scene == 'error') {
          f.failures.add('/rest/1.0/torrents/info/rd9');
        }
        await f.mount(t, width: scene == 'ott_mobile' ? 500 : 1000);
        if (scene == 'raw') {
          f.member('navigateIntoFolder')(f.root.children.single);
        } else if (scene == 'search') {
          f.member('toggleSearch')();
          await t.pump();
          await t.enterText(find.byType(TextField), 'Two');
          (f.member('searchFocusNode') as FocusNode).unfocus();
        } else if (scene.startsWith('ott')) {
          await enterOtt(t, f);
        }
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        if (captureLinux || captureMac) {
          expect(captureLinux ? Platform.isLinux : Platform.isMacOS, isTrue);
          final current = File('lib/screens/playlist_content_view_screen.dart')
              .readAsStringSync()
              .split('/// Original-code characterization seam:')
              .first
              .trimRight();
          final original = Process.runSync('git', [
            'show',
            '67b32702:lib/screens/playlist_content_view_screen.dart',
          ]).stdout.toString().trimRight();
          expect(
            current,
            original,
            reason: 'Capture is allowed only before extraction',
          );
        }
        final host = Platform.isLinux ? 'linux' : 'macos';
        final relative =
            '../../../../goldens/playlist_content/$host/$scene.png';
        final exists = File(
          'test/goldens/playlist_content/$host/$scene.png',
        ).existsSync();
        if (Platform.isLinux && !exists && !captureLinux && !requireLinux) {
          expect(captureLinux, isFalse);
          return;
        }
        await expectLater(
          find.byKey(const ValueKey('playlist-content-canvas')),
          matchesGoldenFile(relative),
        );
      }),
    );
  }
}
