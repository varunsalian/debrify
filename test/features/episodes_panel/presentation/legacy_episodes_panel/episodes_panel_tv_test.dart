import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:debrify/widgets/episode_tile.dart';
import 'package:debrify/widgets/season_action_region.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/episodes_panel_fixture.dart';

FocusNode episodeNode(String label) => FocusManager
    .instance
    .rootScope
    .descendants
    .singleWhere((node) => node.debugLabel == label);
Future<void> focusEpisodeNode(WidgetTester t, String label) async {
  episodeNode(label).requestFocus();
  await t.pump();
  expect(FocusManager.instance.primaryFocus!.debugLabel, label);
}

Future<void> key(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyEvent(
    key,
    physicalKey: key == LogicalKeyboardKey.goBack
        ? PhysicalKeyboardKey.escape
        : null,
  );
  await t.pump();
}

Future<void> dismiss(WidgetTester t, EpisodesPanelFixture f) async {
  f.navigator.currentState!.pop();
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets(
    'Classic EpisodesScreen back, dropdown, source keys and terminal pop order',
    (t) async {
      await episodesPanelCase(t, 'classic-screen-keys', 300, (f) async {
        f.television = true;
        f.hasSourcePicker = true;
        await f.mountScreen(t, size: const Size(1920, 1080), pushed: true);
        expect(find.byType(EpisodeTile), findsNWidgets(2));
        await focusEpisodeNode(t, 'catalog-ep-back');
        await key(t, LogicalKeyboardKey.arrowUp);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'catalog-ep-back',
        );
        await key(t, LogicalKeyboardKey.arrowRight);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'catalog-ep-season',
        );
        await key(t, LogicalKeyboardKey.arrowUp);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'catalog-ep-season',
        );
        await key(t, LogicalKeyboardKey.arrowLeft);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'catalog-ep-back',
        );
        await key(t, LogicalKeyboardKey.arrowDown);
        expect(FocusManager.instance.primaryFocus!.debugLabel, 'catalog-ep-0');
        await focusEpisodeNode(t, 'catalog-select-source-btn');
        await key(t, LogicalKeyboardKey.arrowUp);
        await key(t, LogicalKeyboardKey.arrowRight);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'catalog-select-source-btn',
        );
        await key(t, LogicalKeyboardKey.arrowLeft);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'catalog-ep-season',
        );
        await focusEpisodeNode(t, 'catalog-select-source-btn');
        await key(t, LogicalKeyboardKey.arrowDown);
        expect(FocusManager.instance.primaryFocus!.debugLabel, 'catalog-ep-0');
        await focusEpisodeNode(t, 'catalog-ep-back');
        await key(t, LogicalKeyboardKey.arrowRight);
        await key(t, LogicalKeyboardKey.arrowDown);
        expect(FocusManager.instance.primaryFocus!.debugLabel, 'catalog-ep-0');
        final tile = t.widget<EpisodeTile>(find.byType(EpisodeTile).first);
        expect(tile.onMenuAction, isNull);
        expect(tile.onTrackerOptions, isNull);
        tile.onSources();
        expect(f.calls, ['item:false']);
        expect(f.navigator.currentState!.canPop(), isFalse);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Host'), findsOneWidget);
      });
    },
  );
  for (final activation in [
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.goBack,
  ]) {
    testWidgets(
      'Classic back invokes live host callback for ${activation.keyLabel}',
      (t) async {
        await episodesPanelCase(
          t,
          'back-${activation.keyId}',
          301 + activation.keyId % 100,
          (f) async {
            f.television = true;
            f.custom = false;
            f.chrome = true;
            await f.mount(t);
            await focusEpisodeNode(t, 'catalog-ep-back');
            await key(t, activation);
            expect(f.calls, ['back']);
          },
        );
      },
    );
  }
  testWidgets(
    'Classic Trakt rate and other-tracker options gates remain independent',
    (t) async {
      await episodesPanelCase(t, 'classic-menu-gates', 310, (f) async {
        await t.runAsync(
          () => f.authenticate({TrackingSource.trakt, TrackingSource.simkl}),
        );
        f.custom = false;
        f.chrome = true;
        await f.mountScreen(t, size: const Size(1920, 1080));
        final tile = t.widget<EpisodeTile>(find.byType(EpisodeTile).first);
        expect(tile.onMenuAction, isNotNull);
        expect(tile.onTrackerOptions, isNotNull);
        tile.onMenuAction!(TraktEpisodeMenuAction.rate);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Rate this item'), findsOneWidget);
        await dismiss(t, f);
        tile.onTrackerOptions!();
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Mark as Watched'), findsOneWidget);
        expect(find.text('Rate on Trakt'), findsOneWidget);
      });
    },
  );
  for (final left in [true, false]) {
    testWidgets(
      'compact row keys, repeat/up filtering, sheet focus and season refocus left=$left',
      (t) async {
        await episodesPanelCase(t, 'compact-keys-$left', left ? 320 : 321, (
          f,
        ) async {
          f.custom = false;
          f.compact = true;
          f.television = true;
          f.hasLeft = left;
          await f.mount(t);
          await focusEpisodeNode(t, 'catalog-ep-0');
          final focus = t
              .widgetList<Focus>(find.byType(Focus))
              .singleWhere(
                (widget) => widget.focusNode?.debugLabel == 'catalog-ep-0',
              );
          KeyEvent event(Type kind, LogicalKeyboardKey logical) =>
              kind == KeyUpEvent
              ? KeyUpEvent(
                  physicalKey: PhysicalKeyboardKey.arrowLeft,
                  logicalKey: logical,
                  timeStamp: Duration.zero,
                )
              : KeyRepeatEvent(
                  physicalKey: PhysicalKeyboardKey.arrowLeft,
                  logicalKey: logical,
                  timeStamp: Duration.zero,
                );
          expect(
            focus.onKeyEvent!(
              focus.focusNode!,
              event(KeyUpEvent, LogicalKeyboardKey.arrowLeft),
            ),
            KeyEventResult.ignored,
          );
          expect(
            focus.onKeyEvent!(
              focus.focusNode!,
              event(KeyRepeatEvent, LogicalKeyboardKey.select),
            ),
            KeyEventResult.ignored,
          );
          expect(f.calls, isEmpty);
          expect(
            focus.onKeyEvent!(
              focus.focusNode!,
              const KeyDownEvent(
                physicalKey: PhysicalKeyboardKey.arrowLeft,
                logicalKey: LogicalKeyboardKey.arrowLeft,
                timeStamp: Duration.zero,
              ),
            ),
            left ? KeyEventResult.handled : KeyEventResult.ignored,
          );
          expect(f.calls, left ? ['left'] : isEmpty);
          f.calls.clear();
          await key(t, LogicalKeyboardKey.arrowRight);
          await t.pump(const Duration(milliseconds: 400));
          expect(find.text('Play'), findsOneWidget);
          expect(f.calls, isEmpty);
          expectEpisodesPlayFocus();
          expect(
            find.descendant(
              of: find.byWidget(
                FocusManager.instance.primaryFocus!.context!.widget,
              ),
              matching: find.text('Play'),
            ),
            findsOneWidget,
          );
          await dismiss(t, f);
          await focusEpisodeNode(t, 'catalog-ep-0');
          await key(t, LogicalKeyboardKey.space);
          expect(f.calls, ['before', 'quick']);
          f.calls.clear();
          await key(t, LogicalKeyboardKey.select);
          expect(f.calls, ['before', 'quick']);
          final step = t.widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
          );
          step.onPressed!();
          await t.pump();
          await t.pump();
          expect(
            FocusManager.instance.primaryFocus!.debugLabel,
            'catalog-ep-season',
          );
          expect(find.text('Season 2'), findsOneWidget);
        });
      },
    );
  }
  testWidgets('TV unavailable retry autofocus is reached after failed load', (
    t,
  ) async {
    await episodesPanelCase(t, 'unavailable-tv', 330, (f) async {
      f.custom = false;
      f.television = true;
      f.chrome = true;
      f.failMeta = true;
      await f.mount(t, size: const Size(1920, 1080));
      expect(find.text("Couldn't load episodes"), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'catalog-ep-retry',
      );
      expect(f.requests.where((r) => r.url.host == 'api.tvmaze.com'), isEmpty);
      expect(
        f.requests.where(
          (r) =>
              r.url.host == 'api.trakt.tv' && r.url.path.endsWith('/seasons'),
        ),
        hasLength(1),
      );
      expect(find.text('Search for sources'), findsOneWidget);
      await focusEpisodeNode(t, 'catalog-ep-back');
      await key(t, LogicalKeyboardKey.arrowRight);
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'catalog-ep-retry',
      );
      await focusEpisodeNode(t, 'catalog-ep-back');
      await key(t, LogicalKeyboardKey.arrowDown);
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'catalog-ep-retry',
      );
    });
  });
  testWidgets('season short OK lists seasons, held OK opens guarded options', (
    t,
  ) async {
    await episodesPanelCase(t, 'season-hold', 340, (f) async {
      f.custom = false;
      f.chrome = true;
      f.television = true;
      await f.mount(t);
      await focusEpisodeNode(t, 'catalog-ep-season');
      final regions = t
          .widgetList<Focus>(
            find.descendant(
              of: find.byType(SeasonActionRegion),
              matching: find.byType(Focus),
            ),
          )
          .where((w) => !w.canRequestFocus && w.onKeyEvent != null)
          .toList();
      expect(regions, hasLength(1));
      final region = regions.single;
      const down = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.enter,
        logicalKey: LogicalKeyboardKey.select,
        timeStamp: Duration.zero,
      );
      const up = KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.enter,
        logicalKey: LogicalKeyboardKey.select,
        timeStamp: Duration.zero,
      );
      final node = episodeNode('catalog-ep-season');
      expect(region.onKeyEvent!(node, down), KeyEventResult.handled);
      await t.pump(const Duration(milliseconds: 100));
      expect(region.onKeyEvent!(node, up), KeyEventResult.handled);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.widgetWithText(ListTile, 'Season 2'), findsOneWidget);
      expect(find.textContaining('Mark season as'), findsNothing);
      await dismiss(t, f);
      await focusEpisodeNode(t, 'catalog-ep-season');
      region.onKeyEvent!(node, down);
      await t.pump(const Duration(milliseconds: 600));
      await f.until(
        t,
        () => find.text('Mark season as watched locally').evaluate().isNotEmpty,
      );
      await t.pump(const Duration(milliseconds: 400));
      expect(find.widgetWithText(ListTile, 'Season 2'), findsNothing);
      expect(
        find.descendant(
          of: find.byWidget(
            FocusManager.instance.primaryFocus!.context!.widget,
          ),
          matching: find.text('Mark season as watched locally'),
        ),
        findsOneWidget,
      );
      region.onKeyEvent!(node, up);
    });
  });
  for (final identity in ['custom', 'native']) {
    testWidgets('season provider disabling $identity and busy guard', (
      t,
    ) async {
      await episodesPanelCase(
        t,
        'season-$identity',
        identity == 'custom' ? 350 : 351,
        (f) async {
          f.id = identity == 'custom'
              ? CustomSeriesIdentity(
                  f.addon.sourceBindingKey,
                  'custom-season-350',
                ).id
              : 'tmdb:9800351';
          f.show = StremioMeta(
            id: identity == 'custom' ? 'custom-season-350' : f.id,
            imdbId: identity == 'custom' ? f.id : null,
            type: 'series',
            name: f.show.name,
          );
          await t.runAsync(
            () => f.authenticate({
              TrackingSource.trakt,
              TrackingSource.simkl,
              TrackingSource.mdblist,
            }),
          );
          await f.mount(t);
          f.view.seasonOptions!(1);
          f.view.seasonOptions!(1);
          await f.until(
            t,
            () => find
                .text('Mark season as watched locally')
                .evaluate()
                .isNotEmpty,
          );
          await t.pump(const Duration(milliseconds: 400));
          expect(find.text('Mark season as watched locally'), findsOneWidget);
          expect(find.byType(BottomSheet, skipOffstage: false), findsOneWidget);
          expect(find.textContaining('on Trakt'), findsNothing);
          expect(find.textContaining('on MDBList'), findsNothing);
          expect(
            find.textContaining('on Simkl'),
            identity == 'custom' ? findsNothing : findsOneWidget,
          );
        },
      );
    });
  }
  testWidgets(
    'season failure retains pending intent then success refreshes progress',
    (t) async {
      await episodesPanelCase(t, 'season-retry', 360, (f) async {
        await t.runAsync(() => f.authenticate({TrackingSource.simkl}));
        var progressCalls = 0;
        f.progressLoader = () async {
          progressCalls++;
          return {};
        };
        await f.mount(t);
        final initial = progressCalls;
        f.simklFails = true;
        f.view.seasonOptions!(1);
        await f.until(
          t,
          () => find
              .text('Mark season as watched on Simkl')
              .evaluate()
              .isNotEmpty,
        );
        await t.pump(const Duration(milliseconds: 400));
        await t.tap(find.text('Mark season as watched on Simkl'));
        await t.pump();
        await f.until(
          t,
          () => find
              .textContaining('Reopen the season menu to retry.')
              .evaluate()
              .isNotEmpty,
        );
        expect(progressCalls, initial + 1);
        ScaffoldMessenger.of(
          t.element(find.textContaining('Reopen the season menu to retry.')),
        ).clearSnackBars();
        await t.pump(const Duration(milliseconds: 400));
        f.simklFails = false;
        f.view.seasonOptions!(1);
        await f.until(
          t,
          () => find
              .text('Retry: mark season as watched on Simkl')
              .evaluate()
              .isNotEmpty,
        );
        await t.pump(const Duration(milliseconds: 400));
        await t.tap(find.text('Retry: mark season as watched on Simkl'));
        await t.pump();
        await f.until(
          t,
          () => find
              .text('Season 1 marked watched on Simkl.')
              .evaluate()
              .isNotEmpty,
          frame: const Duration(milliseconds: 20),
        );
        expect(progressCalls, initial + 2);
        f.view.seasonOptions!(1);
        await f.until(
          t,
          () => find
              .text('Mark season as watched on Simkl')
              .evaluate()
              .isNotEmpty,
        );
        await t.pump(const Duration(milliseconds: 400));
        expect(
          find.text('Retry: mark season as watched on Simkl'),
          findsNothing,
        );
        f.navigator.currentState!.pop();
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await t.runAsync(SimklStorage.clearSimklAuth);
        f.view.seasonOptions!(1);
        await f.until(
          t,
          () =>
              find.text('Mark season as watched locally').evaluate().isNotEmpty,
        );
        await t.pump(const Duration(milliseconds: 400));
        expect(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.textContaining('on Simkl'),
          ),
          findsNothing,
        );
      });
    },
  );
}
