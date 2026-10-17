import 'dart:async';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/tv_episode_driver.dart';

void main() {
  testWidgets(
    'P17 guide selection dispatches its provider before the next layout frame',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final result = Completer<Map<String, dynamic>?>();
      final requested = <String>[];
      Future<dynamic>? task;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            channelDirectory: tvDirectory,
            requestChannelById: (id) {
              requested.add(id);
              return result.future;
            },
          ),
        );
        final guide = await d.debrifyGuide();
        final dynamic pick = guide.onChannelSelected;
        task =
            d.observe<dynamic>(() => pick(guide.channels.last))
                as Future<dynamic>;
        // Native pause and provider entry need microtasks, not a layout frame.
        // Observe dispatch before a retained-callback omission can leave an
        // orphan guide animation to obscure the missing-provider assertion.
        for (var i = 0; requested.isEmpty && i < 30; i++) {
          await Future<void>.value();
        }
        expect(requested, ['b']);
        expect(result.isCompleted, isFalse);
        result.complete(null);
        await d.f.finish(t, task);
        expect(d.errors, isEmpty);
      } finally {
        if (!result.isCompleted) result.complete(null);
        if (task != null) await d.f.finish(t, task);
        await d.close();
      }
    },
  );
  testWidgets('P17 Escape permits the next guide key before layout is pumped', (
    t,
  ) async {
    final d = TvEpisodeDriver(t);
    await d.initialize();
    try {
      await d.mount(
        screen: VideoPlayerScreen(
          videoUrl: 'https://player.test/a.mp4',
          title: 'A',
          channelDirectory: tvDirectory,
          requestChannelById: (id) async => null,
        ),
      );
      await d.debrifyGuide();
      t
          .widget<Focus>(
            find.byWidgetPredicate(
              (w) => w is Focus && w.focusNode?.debugLabel == 'tvPlayerRoot',
            ),
          )
          .focusNode!
          .requestFocus();
      await d.f.advance(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await t.sendKeyUpEvent(LogicalKeyboardKey.escape);
      final handled = await t.sendKeyDownEvent(LogicalKeyboardKey.keyG);
      await t.sendKeyUpEvent(LogicalKeyboardKey.keyG);
      expect(handled, isTrue);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });
}
