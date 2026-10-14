import 'dart:async';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/stremio_service.dart';
import 'support/identify_inventory_store.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/tv_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/identify_title_driver.dart';
import 'support/trakt_transport.dart';
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

Future<void> identifyTvMenu(IdentifyTitleDriver d) async {
  final menu = await d.menu();
  expect(menu.initialSection.name, 'subtitles');
  expect(FocusManager.instance.primaryFocus?.debugLabel, 'player-menu-panel');
  await d.f.key(d.t, LogicalKeyboardKey.arrowRight);
  await d.f.key(d.t, LogicalKeyboardKey.enter);
  await d.sheet();
}

Future<void> keyboardSearch(IdentifyTitleDriver d) async {
  final t = d.t;
  if (find.byType(TvKeyboardPanel).evaluate().isEmpty) {
    await d.f.key(t, LogicalKeyboardKey.enter);
  }
  final keyboard = t
      .widget<TvKeyboardPanel>(find.byType(TvKeyboardPanel))
      .controller;
  while (keyboard.row < keyboard.rows.length - 1) {
    await d.f.key(t, LogicalKeyboardKey.arrowDown);
  }
  while (keyboard.col < keyboard.rows.last.length - 1) {
    await d.f.key(t, LogicalKeyboardKey.arrowRight);
  }
  expect(keyboard.rows[keyboard.row][keyboard.col].action, TvKeyAction.submit);
  await d.f.key(t, LogicalKeyboardKey.enter);
}

void main() {
  TraktTestTransport.install();
  for (final path in [
    'initial',
    'suffix',
    'submitted',
    'moved focus',
    'edit text',
  ]) {
    testWidgets(
      'identify TV $path real keys preserve handoff activation Back and menu focus',
      (t) async {
        final d = IdentifyTitleDriver(t);
        await d.setupIdentity();
        PlatformUtil.debugSetAndroidTvCached(true);
        final gate = Completer<http.Response>();
        d.catalog = (_) => gate.future;
        try {
          await d.mountIdentity(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/tv-identify.mp4',
              title: path == 'initial' ? 'Initial title' : '',
            ),
          );
          await identifyTvMenu(d);
          if (path != 'initial') {
            d.searchField.focusNode!.requestFocus();
            await d.f.advance(t);
            if (path == 'suffix') {
              await d.suffix();
            } else {
              await d.f.key(t, LogicalKeyboardKey.enter);
              expect(find.byType(TvKeyboardPanel), findsOneWidget);
              await d.f.key(t, LogicalKeyboardKey.enter);
              expect(d.searchField.controller.text, isNotEmpty);
              expect(d.catalogQueries, isEmpty);
              await d.f.key(t, LogicalKeyboardKey.escape);
              expect(find.byType(TvKeyboardPanel), findsNothing);
              expect(find.text('FIX THE TITLE'), findsOneWidget);
              expect(d.catalogQueries, isEmpty);
              await keyboardSearch(d);
            }
          }
          if (path == 'suffix') {
            // Empty suffix search clears without a request or a handoff.
            expect(d.catalogQueries, isEmpty);
            await d.f.key(t, LogicalKeyboardKey.enter);
            await d.f.key(t, LogicalKeyboardKey.enter);
            await d.f.key(t, LogicalKeyboardKey.escape);
            await d.suffix();
          }
          await d.f.until(t, () => d.catalogQueries.isNotEmpty);
          expect(d.catalogQueries, hasLength(1));
          final beforeFocus = FocusManager.instance.primaryFocus;
          FocusNode? moved;
          if (path == 'moved focus') {
            moved = Focus.of(t.element(find.byIcon(Icons.close_rounded)));
            moved.requestFocus();
            await d.f.advance(t);
            expect(FocusManager.instance.primaryFocus, same(moved));
          }
          if (path == 'edit text') {
            final submitted = d.searchField.controller.text;
            await d.f.key(t, LogicalKeyboardKey.enter);
            await d.f.key(t, LogicalKeyboardKey.enter);
            await d.f.key(t, LogicalKeyboardKey.escape);
            expect(d.searchField.controller.text, isNot(submitted));
            expect(d.catalogQueries, hasLength(1));
          }
          gate.complete(d.response(d.metas));
          await d.found('Chosen title');
          await d.f.advance(t);
          if (path == 'submitted') {
            expect(
              FocusManager.instance.primaryFocus?.debugLabel,
              'identify-title-first-result',
            );
            await t.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
            await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
            await t.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
            await d.f.advance(t);
            expect(d.catalogQueries, hasLength(1));
            // Restore the first result using traversal, then activate via Select.
            final tile = find
                .ancestor(
                  of: find.text('Chosen title'),
                  matching: find.byType(InkWell),
                )
                .first;
            t.widget<InkWell>(tile).focusNode!.requestFocus();
            await d.f.advance(t);
            await d.f.key(t, LogicalKeyboardKey.select);
            await d.f.until(t, () => d.subtitlePaths.isNotEmpty);
            await d.f.actions.settle(t);
            expect(d.panel.subtitleIdentityLabel, 'Subtitles for Chosen title');
            expect(
              FocusManager.instance.primaryFocus?.debugLabel,
              'player-menu-panel',
            );
          } else {
            expect(
              FocusManager.instance.primaryFocus?.debugLabel,
              isNot('identify-title-first-result'),
            );
            if (path == 'moved focus') {
              expect(FocusManager.instance.primaryFocus, same(moved));
            }
            if (path == 'initial') {
              expect(FocusManager.instance.primaryFocus, same(beforeFocus));
            }
            await d.f.advance(t, const Duration(milliseconds: 500));
            await d.f.key(t, LogicalKeyboardKey.escape);
            await d.f.advance(t);
            await d.f.advance(t, const Duration(milliseconds: 350));
            expect(find.text('FIX THE TITLE'), findsNothing);
            expect(
              FocusManager.instance.primaryFocus?.debugLabel,
              'player-menu-panel',
            );
          }
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) gate.complete(d.response([]));
          await removeFixture(d);
          PlatformUtil.debugSetAndroidTvCached(false);
        }
      },
    );
  }
  for (final outcome in ['empty', 'inventory error']) {
    testWidgets(
      'identify TV submitted $outcome cancels handoff before a later suffix response',
      (t) async {
        final d = IdentifyTitleDriver(t, committed: false);
        await d.setupIdentity();
        PlatformUtil.debugSetAndroidTvCached(true);
        IdentifyInventoryStore? store;
        final later = Completer<http.Response>();
        try {
          await d.mountIdentity(
            screen: const VideoPlayerScreen(
              videoUrl: 'https://player.test/cancel.mp4',
              title: '',
            ),
          );
          final pending = d.start(await d.menu());
          await d.sheet();
          if (outcome == 'empty') d.catalog = (_) => d.response([]);
          d.searchField.focusNode!.requestFocus();
          await d.f.advance(t);
          await d.f.key(t, LogicalKeyboardKey.enter);
          await d.f.key(t, LogicalKeyboardKey.enter);
          if (outcome == 'inventory error') {
            StremioService.instance.invalidateCache();
            store = await t.runAsync(IdentifyInventoryStore.install);
          }
          await keyboardSearch(d);
          await d.found(
            outcome == 'empty'
                ? 'No IMDb-backed results found'
                : 'Search failed. Try again.',
          );
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            isNot('identify-title-first-result'),
          );
          store?.restore();
          StremioService.instance.invalidateCache();
          d.catalog = (_) => later.future;
          await d.suffix();
          await d.f.until(
            t,
            () => d.catalogQueries.length == (outcome == 'empty' ? 2 : 1),
          );
          d.searchField.focusNode!.requestFocus();
          await d.f.advance(t);
          expect(later.isCompleted, isFalse);
          later.complete(d.response(d.metas));
          await d.found('Chosen title');
          await d.f.advance(t);
          final result = t.widget<InkWell>(
            find
                .ancestor(
                  of: find.text('Chosen title'),
                  matching: find.byType(InkWell),
                )
                .first,
          );
          expect(result.focusNode!.hasFocus, isFalse);
          expect(d.searchField.focusNode!.hasPrimaryFocus, isTrue);
          Focus.of(t.element(find.byIcon(Icons.close_rounded))).requestFocus();
          await d.f.advance(t);
          await d.dismiss();
          expect(await d.f.finish(t, pending), isNull);
          expect(d.errors, isEmpty);
        } finally {
          store?.restore();
          if (!later.isCompleted) later.complete(d.response([]));
          await removeFixture(d);
          PlatformUtil.debugSetAndroidTvCached(false);
        }
      },
    );
  }
}
