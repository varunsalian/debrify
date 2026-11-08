import 'package:debrify/widgets/iptv/iptv_empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Size size, {VoidCallback? onAdd}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: IptvEmptyState(onAddPlaylist: onAdd),
      ),
    ),
  ),
);

void main() {
  testWidgets('a short pane scrolls instead of overflowing', (tester) async {
    // A folding phone passes through heights like this mid-fold; the fixed
    // column used to overflow here.
    var added = 0;
    await tester.pumpWidget(_host(const Size(460, 240), onAdd: () => added++));

    expect(tester.takeException(), isNull);
    final button = find.text('Add Playlist');
    await tester.scrollUntilVisible(button, 80);
    await tester.tap(button);
    expect(added, 1);
  });

  testWidgets('a tall pane keeps the content centred', (tester) async {
    await tester.pumpWidget(_host(const Size(600, 800), onAdd: () {}));

    expect(tester.takeException(), isNull);
    final title = tester.getCenter(find.text('No IPTV Playlists'));
    final pane = tester.getRect(find.byType(IptvEmptyState));
    expect(title.dx, moreOrLessEquals(pane.center.dx, epsilon: 1));
    final column = tester.getRect(find.byType(Column).first);
    expect(column.center.dy, moreOrLessEquals(pane.center.dy, epsilon: 1));
  });
}
