import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SettingsSearchEntry entry(String title, String category) => SettingsSearchEntry(
  icon: Icons.link_rounded,
  title: title,
  subtitle: '',
  category: category,
  keywords: const [],
  onTap: () async {},
);

void main() {
  Finder headings(String label) =>
      find.widgetWithText(SettingsSectionLabel, label.toUpperCase());

  testWidgets('a category that reappears later renders one heading, not two', (
    tester,
  ) async {
    // The index is a long hand-maintained list; one row in the wrong place
    // used to produce Connections → Trackers → Connections, i.e. a duplicate
    // heading and a section split in half.
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsSearchPage(
          entries: [
            entry('Real Debrid', 'Connections'),
            entry('Trakt', 'Trackers'),
            entry('Jackett & Prowlarr', 'Connections'),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(headings('Connections'), findsOneWidget);
    expect(headings('Trackers'), findsOneWidget);
    expect(find.text('Jackett & Prowlarr'), findsOneWidget);
  });

  testWidgets('an already-grouped index keeps its order', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsSearchPage(
          entries: [
            entry('Real Debrid', 'Connections'),
            entry('Jackett & Prowlarr', 'Connections'),
            entry('Trakt', 'Trackers'),
            entry('General thing', 'General'),
          ],
        ),
      ),
    );
    await tester.pump();

    // Categories keep first-appearance order; rows keep theirs within one.
    final order = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where(
          (s) => const {
            'CONNECTIONS',
            'TRACKERS',
            'GENERAL',
            'Real Debrid',
            'Jackett & Prowlarr',
            'Trakt',
            'General thing',
          }.contains(s),
        )
        .toList();

    expect(order, [
      'CONNECTIONS',
      'Real Debrid',
      'Jackett & Prowlarr',
      'TRACKERS',
      'Trakt',
      'GENERAL',
      'General thing',
    ]);
  });
}
