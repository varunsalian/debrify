import 'package:debrify/features/home/presentation/home_classic_navigation.dart';
import 'package:debrify/features/home/presentation/home_stage_rows.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Classic skips empty rows, clamps columns and preserves edge ordering',
    () {
      const first = HomeRail(sectionIndex: 0);
      const empty = HomeRail(sectionIndex: 1);
      const last = HomeRail(sectionIndex: 2);
      var rows = [first, empty, last];
      final nodes = [FocusNode(), FocusNode()];
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
      final events = <String>[];
      var loading = false;
      var more = true;
      var continuation = false;
      final navigation = HomeClassicNavigation(
        rails: () => rows,
        rowIdOf: (rail) => '${rail.sectionIndex}',
        nodesFor: (rail) => rail == empty ? [] : nodes,
        requestFocus: (_, column) => events.add('focus:$column'),
        leaveTop: () => events.add('top'),
        loadingMore: () => loading,
        hasMore: () => more,
        focusContinuation: () {
          events.add('continuation');
          return continuation;
        },
        loadMore: () => events.add('load'),
        deferDown: (id, col) => events.add('defer:$id:$col'),
      );
      navigation.move('0', 1, 8);
      expect(events, ['focus:1']);
      events.clear();
      navigation.move('2', -1, -2);
      expect(events, ['focus:0']);
      events.clear();
      navigation.move('0', -1, 0);
      expect(events, ['top']);
      events.clear();
      navigation.move('2', 1, 8);
      expect(events, ['continuation', 'load', 'defer:2:8']);
      events.clear();
      continuation = true;
      navigation.move('2', 1, 8);
      expect(events, ['continuation']);
      events.clear();
      loading = true;
      more = false;
      navigation.move('2', 1, 8);
      expect(events, ['defer:2:8']);
      events.clear();
      rows = [last, empty, first];
      navigation.move('2', 1, 0);
      expect(events, ['focus:0']);
      events.clear();
      rows = [first];
      navigation.move('2', 1, 0);
      expect(events, isEmpty);
      expect(navigation.focusAt(1, 0), isFalse);
    },
  );
}
