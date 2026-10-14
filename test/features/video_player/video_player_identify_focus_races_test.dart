import 'dart:async';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/identify_focus_binding.dart';
import 'support/identify_title_driver.dart';
import 'support/trakt_transport.dart';
import 'video_player_identify_tv_test.dart' show keyboardSearch;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

Future<void> closeFocusedSheet(IdentifyTitleDriver d) async {
  if (find.text('FIX THE TITLE').evaluate().isEmpty) return;
  Focus.of(d.t.element(find.byIcon(Icons.close_rounded))).requestFocus();
  await d.f.advance(d.t);
  await d.dismiss();
}

void main() {
  final binding = IdentifyFocusBinding();
  TraktTestTransport.install();
  for (final event in [
    'dispose player',
    'dismiss sheet',
    'move focus',
    'empty result',
  ]) {
    testWidgets(
      'identify TV result focus queued across $event respects live guards and cancellation',
      (t) async {
        final d = IdentifyTitleDriver(t);
        await d.setupIdentity();
        PlatformUtil.debugSetAndroidTvCached(true);
        final gate = Completer<http.Response>();
        d.catalog = (_) => gate.future;
        try {
          await d.mountIdentity(
            screen: const VideoPlayerScreen(
              videoUrl: 'https://player.test/focus.mp4',
              title: '',
            ),
            rooted: true,
          );
          final menu = await d.menu();
          final pending = d.start(menu);
          await d.sheet();
          d.searchField.focusNode!.requestFocus();
          await d.f.advance(t);
          await d.f.key(t, LogicalKeyboardKey.enter);
          await d.f.key(t, LogicalKeyboardKey.enter);
          await keyboardSearch(d);
          await d.f.until(t, () => d.catalogQueries.isNotEmpty);
          binding.hold = true;
          gate.complete(d.response(event == 'empty result' ? [] : d.metas));
          if (event == 'empty result') {
            await d.found('No IMDb-backed results found');
            expect(binding.pending, isEmpty);
          } else {
            await d.f.until(t, () => binding.pending.isNotEmpty);
            await d.found('Chosen title');
            final tile = find
                .ancestor(
                  of: find.text('Chosen title'),
                  matching: find.byType(InkWell),
                )
                .first;
            final target = t.widget<InkWell>(tile).focusNode!;
            expect(target.hasFocus, isFalse);
            if (event == 'dispose player') {
              await d.removePlayer();
            } else if (event == 'dismiss sheet') {
              await closeFocusedSheet(d);
            } else {
              final node = Focus.of(
                t.element(find.byIcon(Icons.close_rounded)),
              );
              node.requestFocus();
              await d.f.advance(t);
              expect(FocusManager.instance.primaryFocus, same(node));
            }
            expect(binding.pending, hasLength(1));
            expect(binding.release, returnsNormally);
            await d.f.advance(t);
            if (event != 'dismiss sheet') expect(target.hasFocus, isFalse);
          }
          binding.release();
          if (event != 'dismiss sheet') await closeFocusedSheet(d);
          expect(await d.f.finish(t, pending), isNull);
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) gate.complete(d.response([]));
          binding.release();
          await removeFixture(d);
          PlatformUtil.debugSetAndroidTvCached(false);
        }
      },
    );
  }
}
