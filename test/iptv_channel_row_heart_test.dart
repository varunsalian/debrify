import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/widgets/iptv/iptv_channel_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The trailing heart on pointer devices asks WHERE a channel should go
/// instead of assuming Favorites — the picker offers Favorites and "Create
/// new list", so the plain case still costs one tap.
///
/// The TV hold gesture is deliberately NOT the same: with no lists of the
/// user's own, HOLD OK stays a direct favorite toggle rather than growing a
/// dialog. A tap is cheap and reversible; a held remote button is neither.
void main() {
  Widget harness({
    required VoidCallback onOpenPicker,
    required ValueChanged<bool> onFavorite,
    bool television = false,
    bool hasCustomLists = false,
    FocusNode? node,
    bool favorited = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: IptvChannelRow(
          channel: IptvChannel(
            name: 'Kannada: Star Suvarna HD',
            url: 'http://h/live/u/p/25814.ts',
            duration: -1,
            contentType: 'live',
          ),
          isTelevision: television,
          focusNode: node,
          isFavorited: favorited,
          onFavoriteToggle: onFavorite,
          onOpenListPicker: onOpenPicker,
          hasCustomLists: hasCustomLists,
          onTap: () {},
        ),
      ),
    );
  }

  testWidgets('tapping the heart opens the list picker, not a blind toggle', (
    tester,
  ) async {
    var picker = 0;
    final favorites = <bool>[];
    await tester.pumpWidget(
      harness(
        onOpenPicker: () => picker++,
        onFavorite: favorites.add,
        favorited: true, // keeps the heart rendered without hover
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.favorite_rounded));
    await tester.pump();

    expect(picker, 1);
    expect(favorites, isEmpty);
  });

  testWidgets('the heart opens the picker even with no lists of your own', (
    tester,
  ) async {
    // The dialog carries Favorites and "Create new list", so it is the right
    // answer before the user has made anything.
    var picker = 0;
    await tester.pumpWidget(
      harness(
        onOpenPicker: () => picker++,
        onFavorite: (_) {},
        hasCustomLists: false,
        favorited: true,
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.favorite_rounded));
    await tester.pump();
    expect(picker, 1);
  });

  testWidgets('TV: HOLD OK stays a favorite toggle when there are no lists', (
    tester,
  ) async {
    var picker = 0;
    final favorites = <bool>[];
    final node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(
      harness(
        onOpenPicker: () => picker++,
        onFavorite: favorites.add,
        television: true,
        hasCustomLists: false,
        node: node,
      ),
    );
    node.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    // Two pumps: the first starts the hold ticker (elapsed 0), the second
    // advances it past the 500ms hold.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(favorites, [true]);
    expect(picker, 0);
  });

  testWidgets('TV: HOLD OK opens the picker once the user has lists', (
    tester,
  ) async {
    var picker = 0;
    final favorites = <bool>[];
    final node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(
      harness(
        onOpenPicker: () => picker++,
        onFavorite: favorites.add,
        television: true,
        hasCustomLists: true,
        node: node,
      ),
    );
    node.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    // Two pumps: the first starts the hold ticker (elapsed 0), the second
    // advances it past the 500ms hold.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(picker, 1);
    expect(favorites, isEmpty);
  });

  testWidgets('a touch long-press ON the heart still reaches the picker', (
    tester,
  ) async {
    // Tooltip installs its own LongPressGestureRecognizer on pointer-down for
    // touch devices, deeper in the tree than the row's GestureDetector, so it
    // wins the arena and the row's long-press never fires. The label must not
    // eat the gesture it is describing.
    var picker = 0;
    await tester.pumpWidget(
      harness(
        onOpenPicker: () => picker++,
        onFavorite: (_) {},
        favorited: true,
      ),
    );
    await tester.pump();

    await tester.longPress(find.byIcon(Icons.favorite_rounded));
    await tester.pumpAndSettle();

    expect(picker, 1);
  });
}
