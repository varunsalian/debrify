import 'package:debrify/features/discover/presentation/discover_focus.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'source restoration waits for reattachment and ignores retired route',
    (tester) async {
      final focus = DiscoverFocus();
      var current = true;
      var notifications = 0;
      focus.focused.addListener(() => notifications++);
      const title = StremioMeta(id: 'one', type: 'movie', name: 'One');
      focus.selectTitle(title);
      expect(focus.focused.value, same(title));
      expect(notifications, 1);
      focus.restoreSource(isCurrent: () => current);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Focus(focusNode: focus.source, child: const SizedBox()),
        ),
      );
      await tester.pump();
      expect(focus.source.hasFocus, isTrue);
      focus.restoreSource(isCurrent: () => current);
      current = false;
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
