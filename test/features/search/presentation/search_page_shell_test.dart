import 'package:debrify/features/home/presentation/home_spotlight_search_button.dart';
import 'package:debrify/features/search/models/search_mode.dart';
import 'package:debrify/features/search/presentation/search_page_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    await tester.tap(find.byType(HomeSpotlightSearchButton));
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
