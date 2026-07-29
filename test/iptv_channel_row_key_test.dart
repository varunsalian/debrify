import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/widgets/iptv/iptv_channel_row.dart';

/// A favoritable TV row plays on OK key-UP (so a held OK can favorite
/// instead). That makes it vulnerable to a key-up it never started: when
/// selecting a source collapses the source rail and moves focus onto the
/// first channel while OK is still down, the row would receive only the
/// key-up and auto-play. It must ignore a key-up with no matching key-down.
void main() {
  Future<(FocusNode row, FocusNode sibling)> pumpRow(
    WidgetTester tester, {
    required VoidCallback onTap,
  }) async {
    final node = FocusNode(debugLabel: 'row');
    final sibling = FocusNode(debugLabel: 'sibling');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // Stands in for the source-rail chip that OK was pressed on.
              Focus(focusNode: sibling, child: const SizedBox(height: 20)),
              IptvChannelRow(
                channel: IptvChannel(
                  name: 'Sky Sports F1',
                  url: 'http://h/live/u/p/1.ts',
                  duration: -1,
                  contentType: 'live',
                ),
                isTelevision: true,
                focusNode: node,
                // Non-null ⇒ favoritable ⇒ the play-on-key-up path.
                onFavoriteToggle: (_) {},
                onTap: onTap,
              ),
            ],
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();
    return (node, sibling);
  }

  testWidgets('a key-up delivered after focus arrives mid-press does not play',
      (tester) async {
    var taps = 0;
    final (row, sibling) = await pumpRow(tester, onTap: () => taps++);

    // OK pressed while the rail chip (sibling) is focused...
    sibling.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump();
    // ...selection collapses the rail and moves focus onto the row...
    row.requestFocus();
    await tester.pump();
    // ...then OK is released, now delivered to the row.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(taps, 0, reason: 'a key-up this row did not start must not play');
  });

  testWidgets('a real down→up press still plays', (tester) async {
    var taps = 0;
    await pumpRow(tester, onTap: () => taps++);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(taps, 1, reason: 'a genuine quick press plays');
  });

  testWidgets('losing focus mid-press disarms the row', (tester) async {
    var taps = 0;
    final (row, _) = await pumpRow(tester, onTap: () => taps++);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump();
    // Focus moves away before release (e.g. the user arrows off).
    row.unfocus();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(taps, 0, reason: 'an abandoned press must not play');
  });
}
