import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/utils/format_tag_detector.dart';
import 'package:debrify/widgets/format_badge.dart';
import 'package:debrify/widgets/source_row.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: child)),
  );

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
