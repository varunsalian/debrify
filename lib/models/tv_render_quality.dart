/// How the Android TV UI is rastered — see
/// [StorageService.getTvRenderQuality]. Three states, not a switch: the
/// automatic branch is the ABSENCE of the stored pref, because that absence is
/// what lets MainActivity keep making the device-capability call.
enum TvRenderQuality {
  /// Let MainActivity decide (GLES2-class hardware gets the 720p buffer).
  auto,

  /// Always raster at the panel's own resolution.
  sharp,

  /// Always raster at ~720p and let the TV's scaler upscale.
  fast,
}
