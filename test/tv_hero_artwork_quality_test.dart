import 'package:debrify/models/tv_hero_artwork_quality.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tv_hero_artwork_quality_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('automatic follows the active low-resolution TV mode', () {
    expect(
      TvHeroArtworkQuality.automatic.resolve(lowResRenderActive: true),
      TvHeroArtworkDecodeSize.performance,
    );
    expect(
      TvHeroArtworkQuality.automatic.resolve(lowResRenderActive: false),
      TvHeroArtworkDecodeSize.fullHd,
    );
    expect(
      TvHeroArtworkQuality.automatic.resolve(lowResRenderActive: null),
      TvHeroArtworkDecodeSize.fullHd,
    );
  });

  test('explicit modes ignore the TV render mode', () {
    expect(
      TvHeroArtworkQuality.performance.resolve(lowResRenderActive: false),
      TvHeroArtworkDecodeSize.performance,
    );
    expect(
      TvHeroArtworkQuality.fullHd.resolve(lowResRenderActive: true),
      TvHeroArtworkDecodeSize.fullHd,
    );
  });

  test('decode sizes bound portrait fallbacks as well as landscape art', () {
    expect(TvHeroArtworkDecodeSize.performance.landscapeWidth, 1080);
    expect(TvHeroArtworkDecodeSize.performance.posterHeight, 1080);
    expect(TvHeroArtworkDecodeSize.fullHd.landscapeWidth, 1920);
    expect(TvHeroArtworkDecodeSize.fullHd.posterHeight, 1080);
  });

  test(
    'storage defaults safely and round-trips every supported mode',
    () async {
      expect(
        await StorageService.getTvHeroArtworkQuality(),
        TvHeroArtworkQuality.automatic,
      );
      for (final quality in TvHeroArtworkQuality.values) {
        await StorageService.setTvHeroArtworkQuality(quality);
        expect(await StorageService.getTvHeroArtworkQuality(), quality);
      }
    },
  );

  test('unknown stored values fall back to automatic', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tv_hero_artwork_quality': 'future_removed_mode',
    });
    expect(
      await StorageService.getTvHeroArtworkQuality(),
      TvHeroArtworkQuality.automatic,
    );
  });

  test(
    'startup controller resolves Automatic before the first frame',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tv_hero_artwork_quality': 'automatic',
        'tv_low_res_render_active': true,
      });
      await TvHeroArtworkQualityController.warm();
      expect(
        TvHeroArtworkQualityController.decodeSize,
        TvHeroArtworkDecodeSize.performance,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        'tv_hero_artwork_quality': 'automatic',
        'tv_low_res_render_active': false,
      });
      await TvHeroArtworkQualityController.warm();
      expect(
        TvHeroArtworkQualityController.decodeSize,
        TvHeroArtworkDecodeSize.fullHd,
      );
    },
  );

  test(
    'live selection updates both storage and synchronous decode bounds',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tv_low_res_render_active': true,
      });
      await TvHeroArtworkQualityController.setQuality(
        TvHeroArtworkQuality.fullHd,
      );
      expect(
        await StorageService.getTvHeroArtworkQuality(),
        TvHeroArtworkQuality.fullHd,
      );
      expect(
        TvHeroArtworkQualityController.decodeSize,
        TvHeroArtworkDecodeSize.fullHd,
      );
    },
  );
}
