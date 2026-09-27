import 'package:debrify/features/home/presentation/home_hero_trailer_layer.dart';
import 'package:debrify/features/home/presentation/home_stage_scrims.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;
import '../../theme/golden_harness.dart' show disableRuntimeFonts;

void main() {
  setUp(disableRuntimeFonts);
  testWidgets(
    'Canvas theater waits five seconds and key wake keeps shelf focus',
    (tester) async {
      final home = HomeFixture(tester, style: 'canvas');
      home.slow.complete(page('Slow'));
      await home.mount();
      await home.settle();
      final focus = await home.focusFast();
      await home.pump(const Duration(seconds: 3));
      await home.settle();
      final shelfElement = tester.element(find.text('Fast 0').last);
      bool theater() =>
          tester.widget<HomeStageScrims>(find.byType(HomeStageScrims)).theater;
      void playing(bool value) => tester
          .widget<HomeHeroTrailerLayer>(find.byType(HomeHeroTrailerLayer))
          .onPlayingChanged!(value);
      playing(true);
      await home.pump(const Duration(milliseconds: 4999));
      expect(theater(), isFalse);
      await home.pump(const Duration(milliseconds: 1));
      expect(theater(), isTrue);
      expect(focus.hasFocus, isTrue);
      expect(tester.element(find.text('Fast 0').last), same(shelfElement));
      await home.key(LogicalKeyboardKey.keyA);
      await home.pump(Duration.zero);
      expect(theater(), isFalse);
      expect(focus.hasFocus, isTrue);
      await home.pump(const Duration(milliseconds: 4999));
      expect(theater(), isFalse);
      await home.pump(const Duration(milliseconds: 1));
      expect(theater(), isTrue);
      playing(false);
      await home.pump(Duration.zero);
      expect(theater(), isFalse);
      await home.pump(const Duration(seconds: 6));
      expect(theater(), isFalse);
      await home.dispose();
    },
  );
}
