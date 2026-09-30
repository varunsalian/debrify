import 'dart:async';

import 'package:debrify/services/tracker_title_actions.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lists extends Fake implements TrackerTitleActions {
  final loaded = Completer<List<Map<String, dynamic>>>();
  @override
  Future<List<Map<String, dynamic>>> customLists({
    required bool Function() isCurrent,
  }) => loaded.future;
}

// The list picker loads lists before it can show. A detail page closed during
// that load must not get a picker (or its empty-state feedback) behind it.
void main() {
  Future<({BuildContext context, _Lists lists})> host(
    WidgetTester tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return (context: context, lists: _Lists());
  }

  for (final open in [true, false]) {
    testWidgets('picker after lists load when prompting allowed=$open', (
      tester,
    ) async {
      final h = await host(tester);
      var promptable = true;
      unawaited(
        showTraktCustomListPickerDialog(
          h.context,
          actions: h.lists,
          isCurrent: () => promptable,
        ),
      );
      await tester.pump();
      promptable = open;
      h.lists.loaded.complete([
        {
          'name': 'Weekend',
          'ids': {'slug': 'weekend'},
        },
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Weekend'), open ? findsOneWidget : findsNothing);
    });
  }
}
