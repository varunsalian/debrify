import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/widgets/iptv/iptv_channel_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final television in [false, true]) {
    testWidgets('CW hold opens options without playing (TV: $television)', (
      tester,
    ) async {
      var plays = 0;
      var menus = 0;
      var favorites = 0;
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IptvChannelRow(
              channel: IptvChannel(
                name: 'Replay',
                url: 'https://example.com/replay',
                contentType: 'vod',
              ),
              isTelevision: television,
              focusNode: focus,
              onTap: () => plays++,
              onLongPress: () => menus++,
              onFavoriteToggle: (_) => favorites++,
            ),
          ),
        ),
      );
      if (television) {
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      } else {
        await tester.longPress(find.text('Replay'));
      }
      await tester.pump();
      expect(menus, 1);
      expect(plays, 0);
      expect(favorites, 0);
      if (television) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      } else {
        await tester.tap(find.text('Replay'));
      }
      expect(plays, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      focus.dispose();
    });
  }
}
