// The Search sources page with faked collaborators: defaults render, the
// IPTV master toggle gates the playlist rows, writes chain in tap order, a
// write that loses its owner mid-flight is dropped, and a failed write
// reports itself without reverting the toggle.
import 'dart:async';

import 'package:debrify/features/source_search_settings/presentation/source_search_settings_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/source_search_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSource {
  _FakeSource({
    this.playlists = const [],
    this.choices = const SourceSearchChoices(),
    Object? Function()? owner,
  }) : ownerHolder = owner ?? (() => 'profile-1');

  final List<SourceSearchPlaylist> playlists;
  final SourceSearchChoices choices;
  Object? Function() ownerHolder;
  final written = <SourceSearchChoices>[];

  /// When set, writes go through it instead of the plain `written` log: a
  /// test can park a write (a profile switch, a failure) mid-flight.
  Future<void> Function(SourceSearchChoices)? gate;

  Future<void> write(SourceSearchChoices choices) async {
    await gate?.call(choices);
    written.add(choices);
  }
}

Future<void> _mount(
  WidgetTester tester, {
  required _FakeSource source,
  Future<SourceSearchChoices> Function()? read,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: SourceSearchSettingsPage(
        loadPlaylists: () async => source.playlists,
        read: read ?? () async => source.choices,
        write: source.write,
        // Delegate so reassigning `ownerHolder` mid-test is visible.
        owner: () => source.ownerHolder(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const twoPlaylists = [
    (id: 'pl-a', name: 'Movies 24/7'),
    (id: 'pl-b', name: 'Kids TV'),
  ];

  Finder toggleOf(String title) => find.ancestor(
    of: find.text(title),
    matching: find.byType(SettingsToggleTile),
  );

  Future<void> flip(WidgetTester tester, String title) async {
    await tester.tap(toggleOf(title), warnIfMissed: false);
    await tester.pump();
  }

  testWidgets('shows the defaults: both sources on, playlists included', (
    tester,
  ) async {
    await _mount(tester, source: _FakeSource(playlists: twoPlaylists));
    expect(find.text('Search IPTV playlists'), findsOneWidget);
    expect(find.text('Search media servers'), findsOneWidget);
    expect(find.text('Movies 24/7'), findsOneWidget);
    expect(find.text('Kids TV'), findsOneWidget);
    expect(find.text('Included in search'), findsNWidgets(2));
    expect(find.text('Left out of search'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
  });

  testWidgets('playlist rows stay hidden while IPTV is off', (tester) async {
    await _mount(
      tester,
      source: _FakeSource(
        playlists: twoPlaylists,
        choices: const SourceSearchChoices(iptv: false),
      ),
    );
    expect(find.text('Search IPTV playlists'), findsOneWidget);
    expect(find.text('Movies 24/7'), findsNothing);
    expect(find.text('Kids TV'), findsNothing);
  });

  testWidgets('empty playlist list shows the empty line', (tester) async {
    await _mount(tester, source: _FakeSource());
    expect(find.text('No IPTV playlists yet.'), findsOneWidget);
  });

  testWidgets('writes reach write() in tap order, even when one is slow', (
    tester,
  ) async {
    final source = _FakeSource(playlists: twoPlaylists);
    final firstWrite = Completer<void>();
    source.gate = (_) async => firstWrite.future;
    await _mount(tester, source: source);

    // Both toggles are flipped while the first write is still in flight.
    await flip(tester, 'Movies 24/7');
    await flip(tester, 'Search media servers');
    expect(source.written, isEmpty);

    firstWrite.complete();
    await tester.pumpAndSettle();
    expect(source.written, hasLength(2));
    // First entry still searches media servers; the second has both changes.
    expect(source.written[0].mediaServers, isTrue);
    expect(source.written[0].includesPlaylist('pl-a'), isFalse);
    expect(source.written[1].mediaServers, isFalse);
    expect(source.written[1].includesPlaylist('pl-b'), isTrue);
  });

  testWidgets('a write queued under an old profile is dropped after a switch', (
    tester,
  ) async {
    final source = _FakeSource(playlists: twoPlaylists, owner: () => 'p');
    // The first write parks mid-flight so a profile switch lands while the
    // second write is still queued behind it.
    final parked = Completer<void>();
    var first = true;
    final seen = <SourceSearchChoices>[];
    source.gate = (choices) async {
      seen.add(choices);
      if (first) {
        first = false;
        await parked.future;
      }
    };
    await _mount(tester, source: source);

    await flip(tester, 'Search IPTV playlists');
    await flip(tester, 'Search media servers');
    // Profile switch while the second write is still queued.
    source.ownerHolder = () => 'p2';
    parked.complete();
    await tester.pumpAndSettle();
    // Only the write that started under the old profile reached write(); the
    // queued one is dropped instead of landing in the new profile's prefs.
    expect(seen, hasLength(1));
    expect(source.written, hasLength(1));
    // The UI stayed on the new values.
    expect(
      tester.widget<SettingsToggleTile>(toggleOf('Search media servers')).value,
      isFalse,
    );
  });

  testWidgets('a failed write snackbar-fails without reverting the toggle', (
    tester,
  ) async {
    final source = _FakeSource(playlists: twoPlaylists);
    source.gate = (choices) async => throw StateError('disk full');
    await _mount(tester, source: source);

    await flip(tester, 'Search media servers');
    await tester.pumpAndSettle();
    expect(find.text('Could not save search sources'), findsOneWidget);
    final serverToggle = tester.widget<SettingsToggleTile>(
      toggleOf('Search media servers'),
    );
    expect(serverToggle.value, isFalse);
  });

  testWidgets('a failing load shows the load error', (tester) async {
    await _mount(
      tester,
      source: _FakeSource(),
      read: () async => throw StateError('no profile'),
    );
    expect(find.text('Could not load search sources.'), findsOneWidget);
  });
}
