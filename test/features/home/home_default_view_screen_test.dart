import 'dart:async';
import 'package:debrify/features/home/application/home_default_view_dependencies.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;

void main() {
  testWidgets(
    'off-TV Home applies saved keyword mode and refreshes back to catalog',
    (tester) async {
      final first = Completer<String?>();
      var reads = 0;
      final home = HomeFixture(tester, television: false);
      // Off-TV initial loading waits for the full batch before painting rows.
      home.slow.complete(page('Slow'));
      await home.mount(
        wrap: (child) => ProviderScope(
          overrides: [
            homeDefaultViewReaderProvider.overrideWithValue(
              () => ++reads == 1 ? first.future : Future.value('catalog'),
            ),
          ],
          child: child,
        ),
      );
      expect(reads, 1);
      await home.drive(() => first.complete('keyword'));
      await home.settle();
      expect(find.text('Keyword torrent search'), findsOneWidget);
      await home.drive(MainPageBridge.notifyHomeSettingsChanged);
      await home.settle();
      expect(find.text('Keyword torrent search'), findsNothing);
      expect(find.text('Fast 0'), findsWidgets);
      expect(reads, 2);
      await home.dispose();
    },
  );

  testWidgets('TV Home does not read the saved default at startup or refresh', (
    tester,
  ) async {
    final home = HomeFixture(tester);
    await home.mount(
      wrap: (child) => ProviderScope(
        overrides: [
          homeDefaultViewReaderProvider.overrideWithValue(
            () => throw StateError('TV read'),
          ),
        ],
        child: child,
      ),
    );
    await home.drive(() => home.slow.complete(page('Slow')));
    await home.settle();
    await home.drive(MainPageBridge.notifyHomeSettingsChanged);
    await home.settle();
    expect(find.text('Fast 0'), findsWidgets);
    expect(find.text('Keyword torrent search'), findsNothing);
    await home.dispose();
  });
}
