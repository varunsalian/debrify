import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holding UP in the player's channel list scrolls it and stops on channel 1;
/// only a fresh UP there moves on to the filters (source picker), and only a
/// fresh UP on the filters moves on to search.
void main() {
  final channels = [
    for (var n = 1; n <= 5; n++)
      IptvChannel(
        channelNumber: n,
        name: 'Channel $n',
        url: 'https://example.com/$n.m3u8',
        group: 'Sports',
        contentType: 'live',
      ),
  ];

  Future<List<int>> pumpGuide(WidgetTester t, {required int start}) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final played = <int>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IptvChannelSheet(
            channels: channels,
            currentIndex: start,
            categories: const ['Sports'],
            sourceId: 'source-1',
            sourceName: 'My IPTV',
            onChannelSelected: (_, index) async => played.add(index),
            onClose: () {},
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 400));
    return played;
  }

  Future<void> pressOk(WidgetTester t) async {
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump(const Duration(milliseconds: 50));
  }

  testWidgets('a held UP walks to channel 1 and stays in the list', (t) async {
    final played = await pumpGuide(t, start: 3);
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    for (var repeat = 0; repeat < 8; repeat++) {
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await t.pump(const Duration(milliseconds: 200));
    await pressOk(t);
    expect(played, [0]);
  });

  testWidgets('a held UP stops on the filters rather than reaching search', (
    t,
  ) async {
    final played = await pumpGuide(t, start: 0);
    // The fresh press moves to the filters; its repeats must stop there.
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    for (var repeat = 0; repeat < 6; repeat++) {
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await t.pump(const Duration(milliseconds: 50));
    // From the filters DOWN returns to channel 1; from search it would only
    // reach the filters, and OK would then open the source picker.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump(const Duration(milliseconds: 50));
    await pressOk(t);
    expect(played, [0]);
  });

  testWidgets('a fresh UP on channel 1 still moves to the filters', (t) async {
    final played = await pumpGuide(t, start: 0);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump(const Duration(milliseconds: 50));
    // DOWN from the filters returns to the list, on the same channel.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump(const Duration(milliseconds: 50));
    await pressOk(t);
    expect(played, [0]);
    // UP then OK acts on the filters, not the channel.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump(const Duration(milliseconds: 50));
    await pressOk(t);
    expect(played, [0]);
    await t.pump(const Duration(milliseconds: 400));
  });
}
