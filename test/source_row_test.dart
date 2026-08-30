import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/utils/format_tag_detector.dart';
import 'package:debrify/widgets/format_badge.dart';
import 'package:debrify/widgets/source_row.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: child)),
  );

  Future<(FocusNode row, FocusNode sibling)> pumpTvRow(
    WidgetTester tester, {
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) async {
    final row = FocusNode(debugLabel: 'source-row');
    final sibling = FocusNode(debugLabel: 'opening-control');
    addTearDown(row.dispose);
    addTearDown(sibling.dispose);
    await pump(
      tester,
      Column(
        children: [
          Focus(focusNode: sibling, child: const SizedBox(height: 20)),
          SourceRow(
            title: 'Source',
            subtitle: 'metadata',
            focusNode: row,
            onTap: onTap,
            onLongPress: onLongPress,
            isTelevision: true,
          ),
        ],
      ),
    );
    row.requestFocus();
    await tester.pump();
    return (row, sibling);
  }

  testWidgets('an opening OK key-up without a matching down does not play', (
    tester,
  ) async {
    var taps = 0;
    final (row, sibling) = await pumpTvRow(
      tester,
      onTap: () => taps++,
    );

    sibling.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    row.requestFocus();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(taps, 0, reason: 'the source row did not begin this press');
  });

  testWidgets('a genuine TV OK down-up still taps the source', (tester) async {
    var taps = 0;
    await pumpTvRow(tester, onTap: () => taps++);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('a held TV OK invokes only the source long-press action', (
    tester,
  ) async {
    var taps = 0;
    var holds = 0;
    await pumpTvRow(
      tester,
      onTap: () => taps++,
      onLongPress: () => holds++,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 550));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(holds, 1);
    expect(taps, 0);
  });

  testWidgets('format row shows title, subtitle, cache pill and logos', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    final tags = FormatTagDetector.detect('The.Wire.S01E01.2160p.REMUX.HDR.IMAX.HEVC');
    await pump(
      tester,
      SourceRow(
        title: '2160p REMUX HDR IMAX',
        subtitle: 'REMUX · 2160p · HEVC · 65.6 GB · ↑ 1,204 · Torrentio',
        focusNode: node,
        onTap: () {},
        formatTags: tags,
        cacheLabel: 'TB | PM',
      ),
    );
    expect(find.text('2160p REMUX HDR IMAX'), findsOneWidget);
    expect(find.textContaining('Torrentio'), findsOneWidget);
    expect(find.text('⚡ TB | PM'), findsOneWidget);
    expect(find.byType(FormatBadge), findsNWidgets(tags.length));
  });

  testWidgets('compact row shows quality pill and no format logos', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await pump(
      tester,
      SourceRow(
        title: 'Cyberpunk.Edgerunners.S01.1080p.WEB-DL',
        subtitle: '↑ 640 · 12 GB · EZTV',
        focusNode: node,
        onTap: () {},
        qualityTag: '1080p',
        coverageBadge: 'Season Pack',
      ),
    );
    expect(find.byType(FormatBadge), findsNothing);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('Season Pack'), findsOneWidget);
  });

  testWidgets('source title honors a six-line limit', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await pump(
      tester,
      SourceRow(
        title: 'A very long source title',
        titleMaxLines: 6,
        subtitle: 'metadata',
        focusNode: node,
        onTap: () {},
      ),
    );

    final title = tester.widget<Text>(find.text('A very long source title'));
    expect(title.maxLines, 6);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets(
    'copy action reuses the chevron slot without changing text style',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var copies = 0;
      var cardTaps = 0;
      await pump(
        tester,
        SourceRow(
          title: 'A source title',
          subtitle: 'metadata',
          focusNode: node,
          onTap: () => cardTaps++,
          onCopy: () => copies++,
        ),
      );

      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(
        tester.widget<Text>(find.text('A source title')).style?.fontSize,
        13,
      );

      await tester.tap(find.byTooltip('Copy link'));
      expect(copies, 1);
      expect(cardTaps, 0);
    },
  );

  testWidgets('tap fires onTap (touch)', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var taps = 0;
    await pump(
      tester,
      SourceRow(
        title: 'X',
        subtitle: 'y',
        focusNode: node,
        onTap: () => taps++,
        qualityTag: '720p',
      ),
    );
    await tester.tap(find.byType(SourceRow));
    expect(taps, 1);
  });

  testWidgets('focus visuals keep tracking after the FocusNode is swapped '
      '(toolbar rebuild)', (tester) async {
    // Mirrors _rebuildVisible: the same SourceRow position gets a new FocusNode
    // while the widget stays mounted. Without didUpdateWidget migrating the
    // listener, the play pill would never appear on the new node.
    var node = FocusNode();
    addTearDown(() => node.dispose());

    Widget build(FocusNode n) => MaterialApp(
      home: Scaffold(
        body: SourceRow(
          key: const ValueKey('row'), // reuse the same State across rebuilds
          title: 'X',
          subtitle: 'y',
          focusNode: n,
          onTap: () {},
          isTelevision: true,
          showPlayPill: true,
          qualityTag: '4K',
        ),
      ),
    );

    await tester.pumpWidget(build(node));

    // Swap in a fresh node (old one disposed post-frame, like the real code).
    final oldNode = node;
    node = FocusNode();
    await tester.pumpWidget(build(node));
    oldNode.dispose();
    await tester.pumpAndSettle(); // let the Focus widget attach the new node

    expect(find.text('Play'), findsNothing);
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget,
        reason: 'listener must have migrated to the new node');
  });

  testWidgets('play pill appears only when focused on TV', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await pump(
      tester,
      SourceRow(
        title: 'X',
        subtitle: 'y',
        focusNode: node,
        onTap: () {},
        isTelevision: true,
        showPlayPill: true,
        qualityTag: '4K',
      ),
    );
    expect(find.text('Play'), findsNothing);
    node.requestFocus();
    await tester.pump();
    expect(find.text('Play'), findsOneWidget);
  });
}
