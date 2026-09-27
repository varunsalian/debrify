import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture;

void main() {
  testWidgets(
    'catalog left edge reads the current sidebar action without rebuilding',
    (tester) async {
      final home = HomeFixture(tester);
      await home.mount();
      final node = await home.focusFast();
      final previous = MainPageBridge.focusTvSidebar;
      addTearDown(() => MainPageBridge.focusTvSidebar = previous);
      var first = 0;
      var second = 0;
      MainPageBridge.focusTvSidebar = () => first++;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(first, 1);
      MainPageBridge.focusTvSidebar = () => second++;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(first, 1);
      expect(second, 1);
      expect(node.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await home.dispose();
    },
  );
}
