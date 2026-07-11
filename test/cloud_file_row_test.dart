import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/widgets/cloud/cloud_file_row.dart';

void main() {
  Widget harness(List<Widget> rows) {
    return MaterialApp(
      home: Scaffold(body: ListView(children: rows)),
    );
  }

  CloudRowAction action(
    String id,
    String label, {
    bool inStrip = false,
    VoidCallback? onSelected,
  }) {
    return CloudRowAction(
      icon: id == 'play'
          ? Icons.play_arrow_rounded
          : id == 'download'
              ? Icons.download
              : Icons.delete_outline,
      label: label,
      showInStrip: inStrip,
      onSelected: onSelected ?? () {},
    );
  }

  testWidgets('tap fires onTap (folder open / video play)', (tester) async {
    var opened = false;
    await tester.pumpWidget(harness([
      CloudFileRow(
        kind: CloudRowKind.folder,
        title: 'Season 1',
        meta: '12.4 GB · Jun 15',
        onTap: () => opened = true,
        actions: [action('download', 'Download', inStrip: true)],
      ),
    ]));
    await tester.tap(find.text('Season 1'));
    expect(opened, isTrue);
    expect(find.text('12.4 GB · Jun 15'), findsOneWidget);
  });

  testWidgets('tap with null onTap opens the ⋮ menu (plain files)',
      (tester) async {
    var downloaded = false;
    await tester.pumpWidget(harness([
      CloudFileRow(
        kind: CloudRowKind.file,
        title: 'subs.srt',
        actions: [
          action('download', 'Download',
              inStrip: true, onSelected: () => downloaded = true),
          action('delete', 'Delete'),
        ],
      ),
    ]));
    await tester.tap(find.text('subs.srt'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Download').last);
    await tester.pumpAndSettle();
    expect(downloaded, isTrue);
  });

  testWidgets('⋮ opens menu listing every action; picking one fires it',
      (tester) async {
    var deleted = false;
    await tester.pumpWidget(harness([
      CloudFileRow(
        kind: CloudRowKind.video,
        title: 'Movie.mkv',
        onTap: () {},
        actions: [
          action('download', 'Download', inStrip: true),
          action('delete', 'Delete', onSelected: () => deleted = true),
        ],
      ),
    ]));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    // Menu lists both the strip action and the menu-only action.
    expect(find.text('Download'), findsWidgets);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets(
      'a chosen menu action still fires if the row unmounts while the menu is '
      'open (background refresh drops the row)', (tester) async {
    var deleted = false;
    late StateSetter setOuter;
    var showRow = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return ListView(
                children: [
                  if (showRow)
                    CloudFileRow(
                      kind: CloudRowKind.video,
                      title: 'Movie.mkv',
                      onTap: () {},
                      actions: [
                        action('delete', 'Delete',
                            onSelected: () => deleted = true),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);

    // Drop the row from the list while its menu route stays open on the
    // (unchanged) root Navigator — this unmounts the row's State before the
    // user picks an item.
    setOuter(() => showRow = false);
    await tester.pump();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue,
        reason: 'the screen-owned action must run regardless of row lifecycle');
  });

  testWidgets('selection mode: tap toggles, primary action suppressed, strip hidden',
      (tester) async {
    var toggled = 0;
    var opened = false;
    await tester.pumpWidget(harness([
      CloudFileRow(
        kind: CloudRowKind.folder,
        title: 'Season 1',
        onTap: () => opened = true,
        actions: [action('download', 'Download', inStrip: true)],
        selectionMode: true,
        selected: false,
        onToggleSelected: () => toggled++,
      ),
    ]));
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.text('Season 1'));
    expect(toggled, 1);
    expect(opened, isFalse);
  });

  testWidgets('DPAD: → enters strip, OK fires, ← returns, ↓ moves to next row',
      (tester) async {
    final row0 = FocusNode(debugLabel: 'row0');
    final row1 = FocusNode(debugLabel: 'row1');
    addTearDown(row0.dispose);
    addTearDown(row1.dispose);
    var played = false;
    var openedFolder = false;

    await tester.pumpWidget(harness([
      CloudFileRow(
        kind: CloudRowKind.folder,
        title: 'Row A',
        onTap: () => openedFolder = true,
        actions: [
          action('play', 'Play', inStrip: true, onSelected: () => played = true),
          action('delete', 'Delete'),
        ],
        focusNode: row0,
      ),
      CloudFileRow(
        kind: CloudRowKind.video,
        title: 'Row B',
        onTap: () {},
        actions: [action('download', 'Download', inStrip: true)],
        focusNode: row1,
      ),
    ]));

    row0.requestFocus();
    await tester.pump();
    expect(row0.hasPrimaryFocus, isTrue);

    // OK on the row = primary action.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(openedFolder, isTrue);

    // → steps into the strip: the row keeps focus but not primary focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(row0.hasPrimaryFocus, isFalse);
    expect(row0.hasFocus, isTrue);

    // OK on the first strip icon fires Play.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(played, isTrue);

    // ← returns to the row.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(row0.hasPrimaryFocus, isTrue);

    // ↓ moves to the next ROW node (never a strip icon — they skip traversal).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(row1.hasPrimaryFocus, isTrue);
  });

  testWidgets('DPAD: ↓ from inside the strip lands on the next row',
      (tester) async {
    final row0 = FocusNode(debugLabel: 'row0');
    final row1 = FocusNode(debugLabel: 'row1');
    addTearDown(row0.dispose);
    addTearDown(row1.dispose);

    await tester.pumpWidget(harness([
      CloudFileRow(
        kind: CloudRowKind.folder,
        title: 'Row A',
        onTap: () {},
        actions: [action('play', 'Play', inStrip: true)],
        focusNode: row0,
      ),
      CloudFileRow(
        kind: CloudRowKind.folder,
        title: 'Row B',
        onTap: () {},
        actions: [action('play', 'Play', inStrip: true)],
        focusNode: row1,
      ),
    ]));

    row0.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(row0.hasFocus, isTrue);
    expect(row0.hasPrimaryFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(row1.hasPrimaryFocus, isTrue);
    expect(row0.hasFocus, isFalse);
  });

  testWidgets('DPAD: → clamps at the last strip icon instead of escaping',
      (tester) async {
    final row0 = FocusNode(debugLabel: 'row0');
    addTearDown(row0.dispose);

    await tester.pumpWidget(harness([
      CloudFileRow(
        kind: CloudRowKind.video,
        title: 'Row A',
        onTap: () {},
        actions: [action('download', 'Download', inStrip: true)],
        focusNode: row0,
      ),
    ]));

    row0.requestFocus();
    await tester.pump();
    // Strip has 2 slots (download + ⋮): step in, to the end, then past it.
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    // Focus is still inside this row (on the ⋮), not stranded elsewhere.
    expect(row0.hasFocus, isTrue);
    expect(row0.hasPrimaryFocus, isFalse);
  });

  testWidgets('space key activates the focused row (keyboard users)',
      (tester) async {
    final row0 = FocusNode(debugLabel: 'row0');
    addTearDown(row0.dispose);
    var opened = false;

    await tester.pumpWidget(harness([
      CloudFileRow(
        kind: CloudRowKind.folder,
        title: 'Row A',
        onTap: () => opened = true,
        actions: [action('download', 'Download', inStrip: true)],
        focusNode: row0,
      ),
    ]));

    row0.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets(
      'dismissing the ⋮ menu restores focus to the ⋮ icon, so OK reopens it '
      'instead of firing the row primary', (tester) async {
    final row0 = FocusNode(debugLabel: 'row0');
    addTearDown(row0.dispose);
    var primaryFired = 0;

    await tester.pumpWidget(harness([
      CloudFileRow(
        kind: CloudRowKind.folder,
        title: 'Row A',
        onTap: () => primaryFired++,
        actions: [action('delete', 'Delete')],
        focusNode: row0,
      ),
    ]));

    // Focus row, → onto the ⋮ (the only strip slot), OK opens the menu.
    row0.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);

    // Dismiss without choosing.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);

    // Focus must be back on the ⋮ (row has focus, but not primary focus)...
    expect(row0.hasFocus, isTrue);
    expect(row0.hasPrimaryFocus, isFalse);

    // ...so OK reopens the menu rather than opening the folder.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(primaryFired, 0);
  });

  testWidgets('near-miss tap around a strip icon hits the icon, not the row',
      (tester) async {
    var opened = false;
    var menuOpened = false;

    await tester.pumpWidget(harness([
      CloudFileRow(
        kind: CloudRowKind.folder,
        title: 'Row A',
        onTap: () => opened = true,
        actions: [action('delete', 'Delete')],
      ),
    ]));

    // Tap 18px below the ⋮ glyph's center: outside the painted 32dp box but
    // inside the padded ~44dp hit target.
    final center = tester.getCenter(find.byIcon(Icons.more_vert));
    await tester.tapAt(center + const Offset(0, 18));
    await tester.pumpAndSettle();
    menuOpened = find.text('Delete').evaluate().isNotEmpty;

    expect(menuOpened, isTrue,
        reason: 'near-miss should open the menu (icon hit zone)');
    expect(opened, isFalse,
        reason: 'near-miss must NOT fire the row primary action');
  });

  testWidgets('badges render on the meta line', (tester) async {
    await tester.pumpWidget(harness([
      CloudFileRow(
        kind: CloudRowKind.folder,
        title: 'Cached thing',
        meta: '8.1 GB',
        badges: const [
          CloudRowBadge('✓ Cached', CloudBadgeKind.ok),
          CloudRowBadge('47%', CloudBadgeKind.warn),
        ],
        onTap: () {},
        actions: [action('download', 'Download', inStrip: true)],
      ),
    ]));
    expect(find.text('✓ Cached'), findsOneWidget);
    expect(find.text('47%'), findsOneWidget);
  });

  testWidgets('compact width (<600) still shows all strip actions',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness([
      CloudFileRow(
        kind: CloudRowKind.folder,
        title: 'A very long folder name that wraps onto a second line on phones',
        meta: '10 files · 8.1 GB',
        onTap: () {},
        actions: [
          action('play', 'Play', inStrip: true),
          action('download', 'Download', inStrip: true),
          action('delete', 'Delete'),
        ],
      ),
    ]));
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    expect(find.byIcon(Icons.download), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });
}
