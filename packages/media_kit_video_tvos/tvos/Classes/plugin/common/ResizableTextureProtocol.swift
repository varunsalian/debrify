#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

public protocol ResizableTextureProtocol: NSObject, FlutterTexture {
  func resize(_ size: CGSize)
  func render(_ size: CGSize)
  // Frees the mpv render context. Must complete before the Dart side calls
  // `mpv_terminate_destroy` on the core handle; freeing lazily in `deinit`
  // (raster thread) races the core teardown and crashes or aborts in mpv.
  func dispose()
}
