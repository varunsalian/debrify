import 'package:debrify/features/search/presentation/keyword_selection_overlay.dart';
import 'package:debrify/features/search/presentation/keyword_toolbar.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final calls = <String>[];
  late List<FocusNode> nodes;
  setUp(() {
    calls.clear();
    nodes = List.generate(5, (_) => FocusNode());
  });
  tearDown(() {
    for (final node in nodes) {
      node.dispose();
    }
  });

  Widget host(Widget child) => MaterialApp(
    home: AppThemeScope(
      theme: AppThemes.legacy,
      child: Scaffold(body: child),
    ),
  );

  Widget toolbar({
    int selected = 0,
    bool selecting = false,
    bool floating = false,
  }) => KeywordToolbar(
    selectionMode: selecting,
    floatingSelect: floating,
    selectableCount: 2,
    selectedCount: selected,
    filterCount: 1,
    showProviderFilter: true,
    providerFilterCount: 1,
    sortLabel: 'Seeders',
    focusNodes: nodes,
    onKey: (index, total, action, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter) {
        action();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    onCancel: () => calls.add('cancel'),
    onDeselectAll: () => calls.add('none'),
    onSelectAll: () => calls.add('all'),
    onAdd: () => calls.add('add'),
    onSort: () => calls.add('sort'),
    onFilters: () => calls.add('filters'),
    onProviders: () => calls.add('providers'),
    onSources: () => calls.add('sources'),
    onSelect: () => calls.add('select'),
  );

  testWidgets('toolbar selection keeps all/none and empty Add behavior', (
    tester,
  ) async {
    await tester.pumpWidget(host(toolbar(selecting: true)));
    await tester.tap(find.text('Add'));
    await tester.tap(find.text('All'));
    expect(calls, ['all']);
    await tester.pumpWidget(host(toolbar(selecting: true, selected: 2)));
    expect(find.text('None'), findsOneWidget);
    expect(find.text('Add · 2'), findsOneWidget);
    nodes[1].requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.tap(find.text('Add · 2'));
    await tester.tap(find.text('Cancel'));
    expect(calls, ['all', 'none', 'add', 'cancel']);
  });

  testWidgets(
    'compact toolbar retains normal actions during floating selection',
    (tester) async {
      await tester.pumpWidget(
        host(toolbar(selecting: true, selected: 2, floating: true)),
      );
      expect(find.text('Cancel'), findsNothing);
      expect(find.byIcon(Icons.checklist_rounded), findsNothing);
      await tester.tap(find.byIcon(Icons.sort_rounded));
      await tester.tap(find.byIcon(Icons.filter_list_rounded));
      await tester.tap(find.byIcon(Icons.hub_rounded));
      await tester.tap(find.byIcon(Icons.dns_rounded));
      expect(calls, ['sort', 'filters', 'providers', 'sources']);
    },
  );

  testWidgets(
    'floating entry and selection bar preserve callbacks and nav clearance',
    (tester) async {
      Widget overlay(bool selecting, int count) => host(
        Stack(
          children: [
            const Positioned.fill(child: SizedBox()),
            KeywordSelectionOverlay(
              selectionMode: selecting,
              selectableCount: 2,
              selectedCount: count,
              floatingNavigation: true,
              onSelect: () => calls.add('select'),
              onCancel: () => calls.add('cancel'),
              onDeselectAll: () => calls.add('none'),
              onSelectAll: () => calls.add('all'),
              onAdd: () => calls.add('add'),
            ),
          ],
        ),
      );
      await tester.pumpWidget(overlay(false, 0));
      await tester.tap(find.byIcon(Icons.checklist_rounded));
      await tester.pumpWidget(overlay(true, 0));
      await tester.tap(find.text('Add'));
      await tester.tap(find.text('All'));
      expect(calls, ['select', 'all']);
      await tester.pumpWidget(overlay(true, 2));
      await tester.tap(find.text('None'));
      await tester.tap(find.text('Add'));
      expect(calls, ['select', 'all', 'none', 'add']);
      final positioned = tester.widget<Positioned>(
        find.descendant(
          of: find.byType(KeywordSelectionOverlay),
          matching: find.byType(Positioned),
        ),
      );
      expect(positioned.right, 108);
      expect(tester.takeException(), isNull);
    },
  );
}
