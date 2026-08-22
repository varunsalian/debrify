/// Android phone/tablet renderer choices for the Flutter media-kit player.
///
/// Android TV uses the native Media3 SurfaceView player and must never read
/// this preference. Other operating systems have different decoder/output
/// APIs, so they retain media-kit's platform defaults.
enum AndroidVideoRendererMode {
  automatic(
    storageKey: 'automatic',
    label: 'Automatic (Compatibility)',
    description: 'Most compatible GPU renderer with safe decoder fallback.',
  ),
  directMediaCodec(
    storageKey: 'direct_mediacodec',
    label: 'MediaCodec + GPU (Recommended)',
    description:
        'Hardware decoding with subtitle, scaling, and video-effect support.',
  ),
  directSurface(
    storageKey: 'direct_surface',
    label: 'Direct Surface (Performance)',
    description:
        'Lowest overhead, but bitmap subtitles and some video features are unavailable.',
  );

  const AndroidVideoRendererMode({
    required this.storageKey,
    required this.label,
    required this.description,
  });

  final String storageKey;
  final String label;
  final String description;

  String? get videoOutput => switch (this) {
    automatic => null,
    directMediaCodec => 'gpu',
    directSurface => 'mediacodec_embed',
  };

  String? get hardwareDecoder => switch (this) {
    automatic => null,
    directMediaCodec || directSurface => 'mediacodec',
  };

  static AndroidVideoRendererMode fromStorage(String? value) {
    if (value == null) return directMediaCodec;
    return values.firstWhere(
      (mode) => mode.storageKey == value,
      orElse: () => automatic,
    );
  }
}
