/// Decode policy for cinematic Home artwork on television devices.
enum TvHeroArtworkQuality {
  /// Match the artwork decode to the TV UI mode. A low-resolution Android TV
  /// surface keeps the smaller decode; tvOS and full-resolution Android TV use
  /// the complete Full HD MetaHub background.
  automatic('automatic'),

  /// Prefer lower memory use and cheaper texture uploads.
  performance('performance'),

  /// Preserve a Full HD landscape source such as MetaHub's 1920x1080 stills.
  fullHd('full_hd');

  const TvHeroArtworkQuality(this.storageValue);

  final String storageValue;

  static TvHeroArtworkQuality fromStorage(String? value) {
    return values.firstWhere(
      (quality) => quality.storageValue == value,
      orElse: () => TvHeroArtworkQuality.automatic,
    );
  }

  TvHeroArtworkDecodeSize resolve({required bool? lowResRenderActive}) {
    return switch (this) {
      TvHeroArtworkQuality.automatic =>
        lowResRenderActive == true
            ? TvHeroArtworkDecodeSize.performance
            : TvHeroArtworkDecodeSize.fullHd,
      TvHeroArtworkQuality.performance => TvHeroArtworkDecodeSize.performance,
      TvHeroArtworkQuality.fullHd => TvHeroArtworkDecodeSize.fullHd,
    };
  }
}

/// Aspect-preserving axis caps: landscape artwork is width-bound, while a
/// portrait poster fallback is height-bound so it cannot become a 1920x2880
/// texture just because the hero requested a wider background.
class TvHeroArtworkDecodeSize {
  const TvHeroArtworkDecodeSize({
    required this.landscapeWidth,
    required this.posterHeight,
  });

  static const performance = TvHeroArtworkDecodeSize(
    landscapeWidth: 1080,
    posterHeight: 1080,
  );
  static const fullHd = TvHeroArtworkDecodeSize(
    landscapeWidth: 1920,
    posterHeight: 1080,
  );

  /// Width-only decode target for a semantic landscape background. Supplying
  /// one axis lets Flutter retain the source aspect ratio.
  final int landscapeWidth;

  /// Height-only decode target for the known portrait poster fallback.
  final int posterHeight;

  @override
  bool operator ==(Object other) =>
      other is TvHeroArtworkDecodeSize &&
      other.landscapeWidth == landscapeWidth &&
      other.posterHeight == posterHeight;

  @override
  int get hashCode => Object.hash(landscapeWidth, posterHeight);
}
