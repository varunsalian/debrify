import '../models/tv_hero_artwork_quality.dart';
import '../utils/tvos_device.dart';
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

  /// Android's low-res render decision, OR'd with the Apple TV hardware
  /// probe. The stored flag is written only by MainActivity, so on tvOS it is
  /// always null — without the probe, `automatic` silently gave a 3 GB
  /// first-gen Apple TV 4K the same 1920px decodes as a 2022 model, and
  /// jetsam killed it the moment the Home board scrolled.
  static Future<bool?> _lowResRenderActive() async {
    final stored = await StorageService.getTvLowResRenderActive();
    if (TvosDevice.isLowMemoryCached) return true;
    return stored;
  }

  /// A memory-safety cap, not a preference default: on a low-memory Apple TV
  /// even an explicitly stored Full HD choice decodes at the performance
  /// size, because honoring it is a supported route straight back to the
  /// jetsam kill this gate exists to prevent. The stored preference itself is
  /// untouched — it applies again on capable hardware.
  static TvHeroArtworkDecodeSize _cap(TvHeroArtworkDecodeSize size) =>
      TvosDevice.isLowMemoryCached ? TvHeroArtworkDecodeSize.performance : size;

  static Future<void> warm() async {
    final values = await Future.wait<Object?>([
      StorageService.getTvHeroArtworkQuality(),
      _lowResRenderActive(),
    ]);
    _quality = values[0] as TvHeroArtworkQuality;
    _decodeSize = _cap(
      _quality.resolve(lowResRenderActive: values[1] as bool?),
    );
  }

  static Future<void> setQuality(TvHeroArtworkQuality quality) async {
    final lowResRenderActive = await _lowResRenderActive();
    await StorageService.setTvHeroArtworkQuality(quality);
    _quality = quality;
    _decodeSize = _cap(
      quality.resolve(lowResRenderActive: lowResRenderActive),
    );
  }
}
