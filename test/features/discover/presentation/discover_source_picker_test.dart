import 'package:debrify/features/discover/presentation/discover_source_picker.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'release and feature gates preserve active-source and addon ordering rules',
    () {
      final node = FocusNode();
      addTearDown(node.dispose);
      final addons = [
        StremioAddon(
          id: 'z',
          name: 'Zulu',
          userAlias: 'My library',
          manifestUrl: '',
          baseUrl: '',
        ),
        StremioAddon(id: 'a', name: 'Alpha', manifestUrl: '', baseUrl: ''),
      ];
      const cases = [
        // Release, auth, selected, discovery, optional entries.
        (false, true, 'mdblist', false, <String>[]),
        (true, false, 'cw', false, <String>[]),
        (true, false, 'mdblist', false, ['mdblist']),
        (true, true, 'cw', true, ['tmdb', 'mdblist']),
        (false, false, 'tmdb', true, ['tmdb']),
        (false, false, 'tmdb', false, <String>[]),
      ];
      for (final (release, authenticated, selected, discovery, optional)
          in cases) {
        final picker = buildDiscoverSourcePicker(
          selected: selected,
          isTelevision: false,
          focusNode: node,
          discoveryEnabled: discovery,
          mdblistEnabled: release,
          mdblistAuthenticated: authenticated,
          addons: addons,
          onSelected: (_) =>
              fail('building must not persist or change selection'),
        );
        expect(picker.options.map((option) => option.value), [
          'cw',
          'trakt',
          'simkl',
          'jellyfin',
          'emby',
          ...optional,
          'a:z',
          'a:a',
        ]);
        expect(picker.value, selected);
        expect(
          picker.options
              .map((option) => option.label)
              .toList()
              .sublist(5 + optional.length),
          ['My library', 'Alpha'],
        );
      }
    },
  );

  for (final television in [false, true]) {
    testWidgets('source selection and borrowed focus work (TV=$television)', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final picked = <String>[];
      var selected = 'cw';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => buildDiscoverSourcePicker(
                selected: selected,
                isTelevision: television,
                focusNode: node,
                discoveryEnabled: false,
                mdblistEnabled: false,
                mdblistAuthenticated: false,
                addons: const [],
                onSelected: (value) {
                  picked.add(value);
                  setState(() => selected = value);
                },
              ),
            ),
          ),
        ),
      );
      if (television) {
        node.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
      } else {
        await tester.tap(find.text('Continue Watching'));
      }
      await tester.pumpAndSettle();
      expect(find.text('TMDB'), findsNothing);
      expect(find.text('MDBList'), findsNothing);
      if (television) {
        // The popup first receives focus on its scope; Down enters its first
        // row, then advances to Trakt. Preserve the existing dropdown grammar.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
      } else {
        await tester.tap(find.text('Trakt'));
      }
      await tester.pumpAndSettle();
      expect(picked, ['trakt']);
      expect(find.text('Trakt'), findsOneWidget);
      // The host can reattach its node when a new source replaces the panel.
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(focusNode: node, child: const SizedBox()),
        ),
      );
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
