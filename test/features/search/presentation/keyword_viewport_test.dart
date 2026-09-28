import 'package:debrify/features/search/presentation/keyword_viewport.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'restoration waits for results, clamps once and source reset clears position',
    (tester) async {
      final viewport = KeywordViewport()..observeScroll();
      viewport.pendingOffset = 10000;
      viewport.restoreAfterLayout(hasResults: false, isCurrent: () => true);
      expect(viewport.pendingOffset, 10000);
      viewport.restoreAfterLayout(hasResults: true, isCurrent: () => true);
      expect(viewport.pendingOffset, isNull);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            height: 100,
            child: ListView(
              controller: viewport.scroll,
              children: List.generate(30, (_) => const SizedBox(height: 100)),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(viewport.lastOffset, viewport.scroll.position.maxScrollExtent);
      viewport.scroll.jumpTo(100);
      viewport.restoreAfterLayout(hasResults: true, isCurrent: () => true);
      await tester.pump();
      expect(viewport.lastOffset, 100);
      viewport.pendingOffset = 200;
      viewport.resetSource();
      expect(viewport.pendingOffset, isNull);
      expect(viewport.scroll.offset, 0);
      expect(viewport.lastOffset, 0);
      await tester.pumpWidget(const SizedBox());
      viewport.dispose();
    },
  );
}
