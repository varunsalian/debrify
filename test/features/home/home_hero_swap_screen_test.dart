import 'package:debrify/features/home/presentation/home_hero_spotlight.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;
import '../../theme/golden_harness.dart' show disableRuntimeFonts;

void main() {
  setUp(disableRuntimeFonts);
  testWidgets('hero waits for focus rest and cancels an A-B-A jiggle', (
    tester,
  ) async {
    final home = HomeFixture(tester, fastCount: 2);
    home.slow.complete(page('Slow'));
    await home.mount();
    await home.settle();
    final first = await home.focusFast();
    final second = Focus.of(tester.element(find.text('Fast 1').last));
    String hero() => tester
        .widget<HomeHeroSpotlight>(find.byType(HomeHeroSpotlight))
        .item
        .name;
    expect(hero(), 'Fast 0');
    second.requestFocus();
    await home.pump(Duration.zero);
    await home.pump(const Duration(milliseconds: 259));
    expect(hero(), 'Fast 0');
    await home.pump(const Duration(milliseconds: 1));
    expect(hero(), 'Fast 1');
    first.requestFocus();
    await home.pump(Duration.zero);
    await home.pump(const Duration(milliseconds: 100));
    second.requestFocus();
    await home.pump(Duration.zero);
    await home.pump(const Duration(milliseconds: 300));
    expect(hero(), 'Fast 1');
    expect(second.hasFocus, isTrue);
    await home.dispose();
  });
}
