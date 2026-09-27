import 'package:debrify/features/home/presentation/home_hero_spotlight.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/utils/tvos_device.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;
import '../../theme/golden_harness.dart' show disableRuntimeFonts;

void main() {
  setUp(disableRuntimeFonts);
  for (final lowMemory in [false, true]) {
    testWidgets('Home shell cleanup follows TV capacity (low=$lowMemory)', (
      tester,
    ) async {
      TvosDevice.debugOverride(lowMemory);
      addTearDown(() {
        TvosDevice.debugOverride(false);
        MainPageBridge.tvChromeDim.value = 0;
        MainPageBridge.tvHeroTint.value = null;
        MainPageBridge.tvAmbientArt.value = null;
        MainPageBridge.tvStageLightsOff.value = false;
      });
      final home = HomeFixture(tester);
      home.slow.complete(page('Slow'));
      await home.mount();
      await home.settle();
      expect(find.byType(HomeHeroSpotlight), findsOneWidget);
      const color = Color(0xFF446688);
      MainPageBridge.tvChromeDim.value = .6;
      MainPageBridge.tvHeroTint.value = color;
      MainPageBridge.tvAmbientArt.value = 'fixture-art';
      MainPageBridge.tvStageLightsOff.value = true;
      await home.dispose();
      expect(MainPageBridge.tvChromeDim.value, lowMemory ? .6 : 0);
      expect(MainPageBridge.tvHeroTint.value, lowMemory ? color : null);
      expect(
        MainPageBridge.tvAmbientArt.value,
        lowMemory ? 'fixture-art' : null,
      );
      expect(MainPageBridge.tvStageLightsOff.value, lowMemory);
    });
  }
}
