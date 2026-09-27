import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:cached_network_image/cached_network_image.dart';
import 'home_mdblist_continuation_screen_test.dart' show FixtureImages;
import 'package:debrify/features/home/application/home_hero_tint_dependencies.dart';
import 'package:debrify/features/home/presentation/home_hero_spotlight.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;
import '../../theme/golden_harness.dart' show disableRuntimeFonts;

void main() {
  late io.Directory images;
  setUpAll(() async {
    images = await io.Directory.systemTemp.createTemp('hero_tint_');
    final file = await io.File('${images.path}/poster.png').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ),
    );
    CachedNetworkImageProvider.defaultCacheManager = FixtureImages(file);
  });
  tearDownAll(() => images.delete(recursive: true));
  setUp(disableRuntimeFonts);
  testWidgets('Home publishes injected artwork tint to hero before shell', (
    tester,
  ) async {
    final response = Completer<Color?>();
    final posters = <String>[];
    final home = HomeFixture(
      tester,
      fastPage: http.Response(
        jsonEncode({
          'metas': [
            {
              'id': 'fixture:Fast:0',
              'type': 'movie',
              'name': 'Fast 0',
              'poster': 'https://fixture.invalid/art',
            },
          ],
        }),
        200,
      ),
    );
    home.slow.complete(page('Slow'));
    await home.mount(
      wrap: (child) => ProviderScope(
        overrides: [
          homeHeroTintResolverProvider.overrideWithValue((poster) {
            posters.add(poster);
            return response.future;
          }),
        ],
        child: child,
      ),
    );
    await home.settle();
    Color? heroTint() => tester
        .widget<HomeHeroSpotlight>(find.byType(HomeHeroSpotlight))
        .tint!
        .value;
    expect(posters, ['https://fixture.invalid/art']);
    expect(heroTint(), isNull);
    const color = Color(0xFF446688);
    final heroAtShellPublication = <Color?>[];
    void onShell() => heroAtShellPublication.add(heroTint());
    MainPageBridge.tvHeroTint.addListener(onShell);
    await home.drive(() => response.complete(color));
    await home.settle();
    MainPageBridge.tvHeroTint.removeListener(onShell);
    expect(heroTint(), color);
    expect(MainPageBridge.tvHeroTint.value, color);
    expect(heroAtShellPublication, [color]);
    await home.dispose();
  });
}
