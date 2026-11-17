import 'package:debrify/screens/video_player/models/channel_entry.dart';
import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The player's other channel lists follow the IPTV sheet: a held UP scrolls
/// to the first channel and stops there instead of jumping into search.
void main() {
  Future<void> holdUp(WidgetTester t, {int repeats = 8}) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    for (var repeat = 0; repeat < repeats; repeat++) {
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> pressOk(WidgetTester t) async {
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> pump(WidgetTester t, Widget guide) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        // The test font is taller than the app's: at full size a channel row
        // overflows by a pixel, which is unrelated to the keys under test.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.9)),
          child: child!,
        ),
        home: Scaffold(body: guide),
      ),
    );
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('channel guide: a held UP stops on the first channel', (t) async {
    final chosen = <String>[];
    await pump(
      t,
      ChannelGuide(
        channels: [
          for (var n = 1; n <= 5; n++)
            ChannelEntry(id: 'c$n', name: 'Channel $n', number: n),
        ],
        currentChannelId: 'c4',
        onChannelSelected: (channel) => chosen.add(channel.id),
        onClose: () {},
      ),
    );
    await holdUp(t);
    await pressOk(t);
    expect(chosen, ['c1']);
  });

  testWidgets('Stremio TV guide: a held UP stops on the first channel', (
    t,
  ) async {
    final switched = <String>[];
    await pump(
      t,
      StremioTvGuideSheet(
        channels: [
          for (var n = 1; n <= 5; n++)
            {'id': 's$n', 'name': 'Stremio $n', 'number': n},
        ],
        currentChannelId: 's4',
        channelSwitchProvider: (id) async {
          switched.add(id);
          return null;
        },
        onChannelSwitched:
            (
              _,
              __,
              ___, {
              contentEpisode,
              contentImdbId,
              contentSeason,
              contentType,
              newSourceIndex,
              newSources,
              nextUp,
              nowPlaying,
              sourceResolver,
              startAtPercent,
            }) {},
        onClose: () {},
      ),
    );
    await holdUp(t);
    await pressOk(t);
    expect(switched, ['s1']);
  });
}
