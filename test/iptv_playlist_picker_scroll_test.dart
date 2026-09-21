import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/widgets/iptv/iptv_filters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final playlists = List.generate(
    20,
    (i) => IptvPlaylist(
      id: '$i',
      name: 'Playlist $i',
      url: 'https://example.test/$i.m3u',
      addedAt: DateTime(2026),
    ),
  );

  Future<void> openPicker(
    WidgetTester tester, {
    required ValueChanged<IptvPlaylist?> onSelected,
    VoidCallback? onAdd,
  }) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => onSelected(
                await showIptvPlaylistPicker(
                  context,
                  playlists: playlists,
                  onAddPlaylist: onAdd,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('phone swipes reach and select the final playlist', (
    tester,
  ) async {
    IptvPlaylist? selected;
    await openPicker(tester, onSelected: (value) => selected = value);
    final scroll = find.byType(SingleChildScrollView);
    for (var i = 0; i < 7; i++) {
      await tester.drag(scroll, const Offset(0, -350));
      await tester.pumpAndSettle();
    }
    expect(find.text('Playlist 19').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Playlist 19'));
    await tester.pumpAndSettle();
    expect(selected?.id, '19');
    expect(tester.takeException(), isNull);
  });

  testWidgets('DPAD scrolls focused rows and reaches Add Playlist', (
    tester,
  ) async {
    var added = false;
    await openPicker(tester, onSelected: (_) {}, onAdd: () => added = true);
    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(find.text('Add Playlist').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(added, isTrue);
    expect(tester.takeException(), isNull);
  });
}
