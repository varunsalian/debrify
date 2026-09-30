import 'package:debrify/ui/core/spotlight_search_button.dart';
import 'package:debrify/features/search/models/search_mode.dart';
import 'package:debrify/features/search/presentation/search_page_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('focused cold-start sheet consumes Back before style arrives', (
    tester,
  ) async {
    final field = FocusNode();
    final query = TextEditingController();
    late StateSetter rebuild;
    late SpotlightSearchSheet sheet;
    final resetOrder = <String>[];
    sheet = SpotlightSearchSheet(
      field: field,
      isForced: () => query.text.isNotEmpty,
      hasText: () => query.text.isNotEmpty,
      isSpotlightSelected: () => false,
      resetSearch: () {
        expect(sheet.isOpen, isTrue);
        expect(field.hasFocus, isTrue);
        resetOrder.add('reset');
        query.clear();
      },
      rebuild: (change) {
        rebuild(change);
        if (!sheet.isOpen) resetOrder.add('closed');
      },
      isCurrent: () => true,
    );
    field.addListener(sheet.onFocusChanged);
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) {
            rebuild = update;
            return Material(
              child: TextField(focusNode: field, controller: query),
            );
          },
        ),
      ),
    );
    field.requestFocus();
    await tester.pump();
    expect(sheet.isOpen, isTrue);
    expect(sheet.close(), isTrue);
    expect(resetOrder, ['reset', 'closed']);
    expect(sheet.close(), isFalse);
    await tester.pumpWidget(const SizedBox());
    field.dispose();
    query.dispose();
  });

  testWidgets(
    'sheet restoration latches silently and retired opening skips focus',
    (tester) async {
      final field = FocusNode();
      var forced = true;
      var current = true;
      var rebuilds = 0;
      final sheet = SpotlightSearchSheet(
        field: field,
        isForced: () => forced,
        hasText: () => false,
        isSpotlightSelected: () => false,
        resetSearch: () => forced = false,
        rebuild: (change) {
          rebuilds++;
          change();
        },
        isCurrent: () => current,
      );
      sheet.observeForcedState();
      forced = false;
      sheet.observeForcedState();
      expect(sheet.isOpen, isTrue);
      expect(rebuilds, 0);
      // A stale Classic latch alone does not consume the host's Back action.
      expect(sheet.close(), isFalse);
      sheet.restore();
      expect(sheet.isOpen, isTrue);
      expect(rebuilds, 1);
      sheet.close();
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(focusNode: field, child: const SizedBox()),
        ),
      );
      sheet.open();
      current = false;
      await tester.pump();
      expect(field.hasFocus, isFalse);
      await tester.pumpWidget(const SizedBox());
      field.dispose();
    },
  );

  testWidgets('route priority builds only the active surface', (tester) async {
    for (final (discover, tv, search, spotlight, expected) in [
      (true, true, false, true, ['discover']),
      (false, true, false, true, ['board']),
      (false, false, false, true, ['spotlight']),
      (false, true, true, false, ['header', 'sources', 'body']),
      (false, false, false, false, ['header', 'sources', 'body']),
    ]) {
      final built = <String>[];
      Widget build(String name) {
        built.add(name);
        return Text(name);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return buildSearchPageShell(
                context: context,
                glassHome: tv && !search,
                discoverMode: discover,
                isTelevision: tv,
                dedicatedSearch: search,
                spotlightActive: () {
                  expect(discover || (tv && !search), isFalse);
                  return spotlight;
                },
                discover: () => build('discover'),
                board: () => build('board'),
                spotlight: () => build('spotlight'),
                header: () => build('header'),
                sourcesBar: () => build('sources'),
                body: () => build('body'),
              );
            },
          ),
        ),
      );
      expect(built, expected);
      if (tv && !search) {
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          Colors.transparent,
        );
      }
    }
  });

  testWidgets('Spotlight sheet opens, closes and hides close when forced', (
    tester,
  ) async {
    var open = false;
    var forced = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              body: buildSpotlightSearchShell(
                context: context,
                sheetOpen: open,
                canClose: !forced,
                onOpen: () => setState(() => open = true),
                onClose: () => setState(() => open = false),
                header: () => const Text('header'),
                sourcesBar: () => const Text('sources'),
                body: () => const Text('content'),
              ),
            );
          },
        ),
      ),
    );
    expect(find.text('header'), findsNothing);
    expect(find.text('content'), findsOneWidget);
    await tester.tap(find.byType(SpotlightSearchButton));
    await tester.pump();
    expect(find.text('header'), findsOneWidget);
    expect(find.text('sources'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide search'));
    await tester.pump();
    expect(find.text('header'), findsNothing);
    update(() {
      open = true;
      forced = true;
    });
    await tester.pump();
    expect(find.text('header'), findsOneWidget);
    expect(find.byTooltip('Hide search'), findsNothing);
  });

  testWidgets('catalog spinner yields to streamed rows and mode routing', (
    tester,
  ) async {
    for (final (mode, empty, queryEmpty, expected) in [
      (SearchMode.keyword, true, true, 'keyword'),
      (SearchMode.lists, true, true, 'lists'),
      (SearchMode.catalog, true, false, 'spinner'),
      (SearchMode.catalog, false, false, 'board'),
      (SearchMode.catalog, false, true, 'prompt'),
    ]) {
      final built = <String>[];
      Widget build(String name) {
        built.add(name);
        return Text(name);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: buildSearchModeContent(
            mode: mode,
            catalogSearching: true,
            catalogEmpty: empty,
            dedicatedSearch: true,
            queryEmpty: queryEmpty,
            keyword: () => build('keyword'),
            lists: () => build('lists'),
            prompt: () => build('prompt'),
            board: () => build('board'),
          ),
        ),
      );
      expect(built, expected == 'spinner' ? isEmpty : [expected]);
      if (expected == 'spinner') {
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      }
    }
  });

  testWidgets('unified Sources mounts only when eligible and shown', (
    tester,
  ) async {
    for (final (tv, search, show) in [
      (true, false, true),
      (false, true, true),
      (false, false, false),
      (false, false, true),
    ]) {
      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: buildUnifiedCatalogSourcesBar(
            isTelevision: tv,
            dedicatedSearch: search,
            show: show,
            sourcesButton: () {
              builds++;
              return const Text('Sources');
            },
          ),
        ),
      );
      expect(builds, !tv && !search && show ? 1 : 0);
    }
  });
}
