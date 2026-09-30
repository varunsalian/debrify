import 'dart:async';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
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

// "Add to List" loads the user's lists before its picker can show. A detail
// page closed during that load must not get the picker behind it, while the
// action itself stays admitted by view/profile currency only.
void main() {
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(ProfileRuntime.debugReset);

  for (final pageLive in [true, false]) {
    testWidgets('Add to List picker after load, detail live=$pageLive', (
      tester,
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
      final lists = _Lists();
      var live = true;
      unawaited(
        handleTraktMenuAction(
          context,
          StremioMeta.fromJson({'id': 'tt1', 'type': 'movie', 'name': 'Title'}),
          TraktItemMenuAction.addToList,
          actions: lists,
          isCurrent: () => true,
          canPrompt: () => live,
        ),
      );
      await tester.pump();
      live = pageLive;
      lists.loaded.complete([
        {
          'name': 'Weekend',
          'ids': {'slug': 'weekend'},
        },
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Weekend'), pageLive ? findsOneWidget : findsNothing);
    });
  }
}
