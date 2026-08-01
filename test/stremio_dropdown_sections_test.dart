import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';

/// Section headers share the dropdown's option list, so the two things that
/// must never happen are a header being picked as a value and a header being
/// shown as the current selection.
void main() {
  const options = [
    StremioDropdownOption<String>.header('__hdr_a__', 'Quick access'),
    StremioDropdownOption('fav', 'Favorites'),
    StremioDropdownOption<String>.header('__hdr_b__', 'Your lists'),
    StremioDropdownOption('wwe', 'wwe'),
  ];

  Future<List<String>> pumpDropdown(
    WidgetTester tester, {
    String value = 'wwe',
  }) async {
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StremioDropdown<String>(
            value: value,
            options: options,
            onSelected: picked.add,
          ),
        ),
      ),
    );
    return picked;
  }

  testWidgets('the closed pill shows the value, never a header',
      (tester) async {
    await pumpDropdown(tester);
    expect(find.text('wwe'), findsOneWidget);
    expect(find.text('QUICK ACCESS'), findsNothing);
  });

  testWidgets('a value that no longer exists falls back to a real option',
      (tester) async {
    // A source can vanish (a deleted list, a removed playlist). The fallback
    // must not land on a section title.
    await pumpDropdown(tester, value: 'gone');
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('QUICK ACCESS'), findsNothing);
  });

  group('lazy picker (past the 30-option threshold)', _lazyPickerTests);

  testWidgets('headers render in the menu but cannot be picked',
      (tester) async {
    final picked = await pumpDropdown(tester);

    await tester.tap(find.text('wwe'));
    await tester.pumpAndSettle();
    expect(find.text('QUICK ACCESS'), findsOneWidget);
    expect(find.text('YOUR LISTS'), findsOneWidget);

    await tester.tap(find.text('QUICK ACCESS'));
    await tester.pumpAndSettle();
    expect(picked, isEmpty, reason: 'a section title is not a source');
    expect(find.text('YOUR LISTS'), findsOneWidget,
        reason: 'and tapping it does not dismiss the menu');

    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(picked, ['fav']);
  });
}

/// The lazy-picker dialog replaces the popup past 30 options — the path the
/// long IPTV lists take, and where sectioning is easiest to get wrong.
void _lazyPickerTests() {
  // 30 is the threshold; go past it so the dialog path is taken.
  final manyOptions = <StremioDropdownOption<String>>[
    const StremioDropdownOption<String>.header('__hdr_a__', 'Quick access'),
    const StremioDropdownOption('fav', 'Favorites'),
    const StremioDropdownOption<String>.header('__hdr_b__', 'Your playlists'),
    for (var i = 0; i < 34; i++) StremioDropdownOption('p$i', 'Playlist $i'),
  ];

  Future<List<String>> openPicker(
    WidgetTester tester, {
    required String value,
    bool isTelevision = false,
  }) async {
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StremioDropdown<String>(
            value: value,
            label: 'Source',
            options: manyOptions,
            isTelevision: isTelevision,
            onSelected: picked.add,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(StremioDropdown<String>));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('the dialog counts sources, not section headings',
      (tester) async {
    await openPicker(tester, value: 'p0');
    // 35 real options; the two headings must not inflate it to 37.
    expect(find.text('35'), findsOneWidget);
    expect(find.text('37'), findsNothing);
  });

  testWidgets('a missing value still anchors TV focus on a real row',
      (tester) async {
    // An invariant, not a regression guard: when the value matches nothing the
    // anchor index falls back to the first real row rather than to index 0,
    // which is a heading. Flutter's focus scope happens to route focus to the
    // first focusable child anyway, so this passes either way today — it is
    // here to catch a future change that makes rows non-focusable or moves
    // focus off the list entirely.
    await openPicker(tester, value: 'deleted', isTelevision: true);
    await tester.pumpAndSettle();

    final focused = FocusManager.instance.primaryFocus;
    expect(focused?.context, isNotNull, reason: 'something must hold focus');
    expect(
      find.descendant(
        of: find.byElementPredicate((e) => identical(e, focused!.context)),
        matching: find.text('Favorites'),
      ),
      findsOneWidget,
      reason: 'focus lands on the first real row, not on the heading above it',
    );
  });

  testWidgets('picking a row returns its value, headings return nothing',
      (tester) async {
    final picked = await openPicker(tester, value: 'p0');

    await tester.tap(find.text('QUICK ACCESS'));
    await tester.pumpAndSettle();
    expect(picked, isEmpty);

    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(picked, ['fav']);
  });
}
