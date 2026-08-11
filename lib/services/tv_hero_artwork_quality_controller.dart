import '../models/tv_hero_artwork_quality.dart';
import 'storage_service.dart';

/// Process-scoped, synchronously readable TV artwork policy.
///
/// [warm] runs before `runApp`, avoiding a first-frame low-quality decode that
/// would immediately be replaced by the stored Full HD choice. Settings can
/// update it live; the Home board's bridge callback performs the rebuild.
class TvHeroArtworkQualityController {
  TvHeroArtworkQualityController._();

  static TvHeroArtworkQuality _quality = TvHeroArtworkQuality.automatic;
  static TvHeroArtworkDecodeSize _decodeSize =
      TvHeroArtworkDecodeSize.performance;

  static TvHeroArtworkQuality get quality => _quality;
  static TvHeroArtworkDecodeSize get decodeSize => _decodeSize;

  static Future<void> warm() async {
    final values = await Future.wait<Object?>([
      StorageService.getTvHeroArtworkQuality(),
      StorageService.getTvLowResRenderActive(),
    ]);
    _quality = values[0] as TvHeroArtworkQuality;
    _decodeSize = _quality.resolve(lowResRenderActive: values[1] as bool?);
  }

  static Future<void> setQuality(TvHeroArtworkQuality quality) async {
    final lowResRenderActive = await StorageService.getTvLowResRenderActive();
    await StorageService.setTvHeroArtworkQuality(quality);
    _quality = quality;
    _decodeSize = quality.resolve(lowResRenderActive: lowResRenderActive);
  }
}
