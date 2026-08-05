import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/widgets/iptv/iptv_command_rail.dart';

IptvPlaylist _m3u(String id, String name) => IptvPlaylist(
  id: id,
  name: name,
  url: 'https://example.com/$id.m3u',
  addedAt: DateTime(2026, 1, 1),
);

void main() {
  // The rail's arrow contract has flip-flopped once already (RIGHT used to
  // select, which meant walking toward the guide silently switched source).
  // These lock the 10-foot rule: arrows move, the centre button acts.
  group('IPTV command rail keys', () {
    late List<String> selected;
    late FocusNode guideNode;

    Widget harness() {
      selected = <String>[];
      guideNode = FocusNode(debugLabel: 'guide');
      final playlists = [_m3u('a', 'Alpha'), _m3u('b', 'Beta')];
      return MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 180,
                child: IptvCommandRail(
                  playlists: playlists,
                  selectedPlaylist: playlists.first,
                  customLists: const [],
                  sourceCounts: const {},
                  favoritesCount: 0,
                  scheduledCount: 0,
                  showScheduled: false,
                  onSelectPlaylist: (p) => selected.add(p.id),
                  onOpenScheduled: () {},
                  onManageSources: () {},
                ),
              ),
              // Stands in for the channel guide sitting to the rail's right.
              Expanded(
                child: Focus(
                  focusNode: guideNode,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('RIGHT walks into the guide instead of selecting', (
      tester,
    ) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      // Focus the second source WITHOUT selecting it.
      final beta = find.text('Beta');
      expect(beta, findsOneWidget);
      Focus.of(tester.element(beta)).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      // The whole point: walking right must not switch source.
      expect(selected, isEmpty);
      // And it must actually leave the rail, or the user is trapped.
      expect(guideNode.hasFocus, isTrue);
    });

    testWidgets('OK selects the focused source', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      final beta = find.text('Beta');
      Focus.of(tester.element(beta)).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(selected, ['b']);
    });
  });
}
