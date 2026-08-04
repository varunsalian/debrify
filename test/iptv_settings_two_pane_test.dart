import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/iptv_settings_two_pane.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

IptvPlaylist _m3u(String id, String name) => IptvPlaylist(
  id: id,
  name: name,
  url: 'https://example.com/$id.m3u',
  addedAt: DateTime(2026),
);

void main() {
  final deleted = <String>[];
  final refreshed = <String>[];
  final defaulted = <String>[];
  var startupToggles = <bool>[];
  var cwToggles = <bool>[];

  Widget harness({
    required List<IptvPlaylist> playlists,
    String? defaultId,
    List<IptvListMeta> lists = const [],
    bool startupEnabled = false,
    GlobalKey<IptvSettingsTwoPaneState>? key,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: IptvSettingsTwoPane(
          key: key,
          playlists: playlists,
          defaultPlaylistId: defaultId,
          refreshingIds: const {},
          customLists: lists,
          startupEnabled: startupEnabled,
          startupMode: StorageService.startupIptvModeLast,
          startupChannelLabel: 'Not set',
          lastLiveChannelLabel: 'CH 2 · SKY',
          hasStartupChannel: false,
          hasLastLiveChannel: true,
          addMethod: 0,
          onAddMethodChanged: (_) {},
          urlFormBuilder: (_) => const Text('URL FORM'),
          fileFormBuilder: (_) => const Text('FILE FORM'),
          xtreamFormBuilder: (_) => const Text('XTREAM FORM'),
          onFocusFirstFormField: () {},
          urlMethodFocusNode: FocusNode(),
          fileMethodFocusNode: FocusNode(),
          xtreamMethodFocusNode: FocusNode(),
          onSetDefault: (p) => defaulted.add(p.id),
          onRefresh: (p) => refreshed.add(p.id),
          onEdit: (_) {},
          onDelete: (p) => deleted.add(p.id),
          onCreateList: () {},
          onListActions: (_) {},
          onToggleStartup: startupToggles.add,
          onStartupModeChanged: (_) {},
          onPickStartupChannel: () {},
          trackContinueWatching: true,
          onToggleTrackContinueWatching: cwToggles.add,
        ),
      ),
    );
  }

  setUp(() {
    deleted.clear();
    refreshed.clear();
    defaulted.clear();
    startupToggles = [];
    cwToggles = [];
  });

  testWidgets('opens on the default source, not on Add', (tester) async {
    await tester.pumpWidget(
      harness(
        playlists: [_m3u('a', 'Freeview'), _m3u('b', 'Sky UK')],
        defaultId: 'b',
      ),
    );
    await tester.pump();

    // The pane shows the default source's detail, and the rail lists both.
    expect(find.text('Remove source'), findsOneWidget);
    expect(find.text('Sky UK'), findsWidgets);
    expect(find.text('URL FORM'), findsNothing);
  });

  testWidgets('with no sources at all it opens on Add', (tester) async {
    await tester.pumpWidget(harness(playlists: const []));
    await tester.pump();

    expect(find.text('URL FORM'), findsOneWidget);
    expect(find.text('No sources yet.'), findsOneWidget);
  });

  testWidgets('every source is ONE dpad stop; actions live in the pane', (
    tester,
  ) async {
    final key = GlobalKey<IptvSettingsTwoPaneState>();
    await tester.pumpWidget(
      harness(
        playlists: [_m3u('a', 'Freeview'), _m3u('b', 'Sky UK')],
        defaultId: 'a',
        key: key,
      ),
    );
    await tester.pump();

    key.currentState!.focusRail();
    await tester.pump();

    // DOWN walks source→source (not through a four-icon strip), so one press
    // moves the pane from the first source to the second.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('Sky UK'), findsWidgets);

    // RIGHT enters the pane, where the actions are.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(refreshed, ['b']);
  });

  testWidgets('LEFT out of the pane returns to the selected source', (
    tester,
  ) async {
    final key = GlobalKey<IptvSettingsTwoPaneState>();
    await tester.pumpWidget(
      harness(playlists: [_m3u('a', 'A'), _m3u('b', 'B')], key: key),
    );
    await tester.pump();

    key.currentState!.focusRail();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // select B
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // into pane
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // back to rail
    await tester.pump();

    // Back on the rail, OK re-enters B's pane — not A's.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(refreshed, ['b']);
  });

  testWidgets(
    'deleting the last source re-homes the pane instead of crashing',
    (tester) async {
      await tester.pumpWidget(harness(playlists: [_m3u('a', 'Only')]));
      await tester.pump();
      expect(find.text('Remove source'), findsOneWidget);

      // The parent reloads with the source gone.
      await tester.pumpWidget(harness(playlists: const []));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('URL FORM'), findsOneWidget);
    },
  );

  testWidgets('an uncached source says so instead of showing 0 channels', (
    tester,
  ) async {
    await tester.pumpWidget(harness(playlists: [_m3u('a', 'Freeview')]));
    await tester.pump();

    expect(find.textContaining('Not loaded yet'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('startup rows only appear once startup is enabled', (
    tester,
  ) async {
    final key = GlobalKey<IptvSettingsTwoPaneState>();
    await tester.pumpWidget(
      harness(playlists: [_m3u('a', 'A')], startupEnabled: false, key: key),
    );
    await tester.pump();

    key.currentState!.focusRail();
    await tester.pump();
    // Down past Add and Channel lists to Startup.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }

    expect(find.text('Start on a channel'), findsOneWidget);
    expect(find.text('Last watched channel'), findsNothing);

    await tester.pumpWidget(
      harness(playlists: [_m3u('a', 'A')], startupEnabled: true, key: key),
    );
    await tester.pump();
    expect(find.text('Last watched channel'), findsOneWidget);
  });

  testWidgets(
    'entering Channel lists lands on a focusable row, not the built-in',
    (tester) async {
      final key = GlobalKey<IptvSettingsTwoPaneState>();
      final actioned = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IptvSettingsTwoPane(
              key: key,
              playlists: [_m3u('a', 'A')],
              defaultPlaylistId: null,
              refreshingIds: const {},
              customLists: const [
                IptvListMeta(
                  id: 'l1',
                  name: 'Sports',
                  position: 0,
                  isBuiltin: false,
                  channelCount: 3,
                ),
              ],
              startupEnabled: false,
              startupMode: StorageService.startupIptvModeLast,
              startupChannelLabel: 'Not set',
              lastLiveChannelLabel: 'x',
              hasStartupChannel: false,
              hasLastLiveChannel: false,
              addMethod: 0,
              onAddMethodChanged: (_) {},
              urlFormBuilder: (_) => const Text('URL FORM'),
              fileFormBuilder: (_) => const Text('FILE FORM'),
              xtreamFormBuilder: (_) => const Text('XTREAM FORM'),
              onFocusFirstFormField: () {},
              urlMethodFocusNode: FocusNode(),
              fileMethodFocusNode: FocusNode(),
              xtreamMethodFocusNode: FocusNode(),
              onSetDefault: (_) {},
              onRefresh: (_) {},
              onEdit: (_) {},
              onDelete: (_) {},
              onCreateList: () => actioned.add('create'),
              onListActions: (l) => actioned.add('actions:${l.id}'),
              onToggleStartup: (_) {},
              onStartupModeChanged: (_) {},
              onPickStartupChannel: () {},
              trackContinueWatching: true,
              onToggleTrackContinueWatching: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      key.currentState!.focusRail();
      await tester.pump();
      // down past Add to Channel lists
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.text('Channel lists'), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // If entering the pane landed on the non-actionable Favorites row,
      // nothing fires and DPAD is stranded.
      expect(actioned, isNotEmpty);
    },
  );

  testWidgets('removing a source does not dispose a node still in the tree', (
    tester,
  ) async {
    final key = GlobalKey<IptvSettingsTwoPaneState>();
    await tester.pumpWidget(
      harness(
        playlists: [_m3u('a', 'A'), _m3u('b', 'B'), _m3u('c', 'C')],
        key: key,
      ),
    );
    await tester.pump();

    key.currentState!.focusRail();
    await tester.pump();
    // Sit on the LAST source, whose rail node a shrinking pool would kill.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    await tester.pumpWidget(harness(playlists: [_m3u('a', 'A')], key: key));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The rail is still usable afterwards.
    key.currentState!.focusRail();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(refreshed, ['a']);
  });

  testWidgets('DOWN at the bottom of the rail stops instead of jumping', (
    tester,
  ) async {
    final key = GlobalKey<IptvSettingsTwoPaneState>();
    await tester.pumpWidget(harness(playlists: [_m3u('a', 'A')], key: key));
    await tester.pump();

    key.currentState!.focusRail();
    await tester.pump();
    // Walk past the end: source, Add, Channel lists, Startup, Continue
    // watching (last, with no recorder in this harness), then extra.
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }

    // Still on Continue watching — not flung sideways into the pane, where OK
    // would have toggled its switch by accident.
    expect(find.text('Track movies and series'), findsOneWidget);
    expect(cwToggles, isEmpty);
    expect(startupToggles, isEmpty);
  });

  testWidgets('hover leaves the pane alone; only a click changes it', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        playlists: [_m3u('a', 'Alpha'), _m3u('b', 'Beta')],
        defaultId: 'a',
      ),
    );
    await tester.pump();
    expect(find.textContaining('example.com/a.m3u'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Beta')));
    await tester.pump();

    // Crossing the rail with the pointer must not swap the pane out from
    // under whatever is being read.
    expect(find.textContaining('example.com/a.m3u'), findsOneWidget);
    expect(find.textContaining('example.com/b.m3u'), findsNothing);

    await tester.tap(find.text('Beta'));
    await tester.pump();
    expect(find.textContaining('example.com/b.m3u'), findsOneWidget);
  });

  testWidgets('a click in the row padding selects, not just on the text', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        playlists: [_m3u('a', 'Alpha'), _m3u('b', 'Beta')],
        defaultId: 'a',
      ),
    );
    await tester.pump();

    // Aim near the top edge of Beta's row — inside the entry, outside the
    // text it paints. deferToChild hit-testing would drop this.
    final row = tester.getRect(
      find
          .ancestor(
            of: find.text('Beta'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.tapAt(Offset(row.center.dx, row.top + 3));
    await tester.pump();

    expect(find.textContaining('example.com/b.m3u'), findsOneWidget);
  });
}
