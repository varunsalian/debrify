#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

public protocol ResizableTextureProtocol: NSObject, FlutterTexture {
  /// Free the mpv render context before the player handle is destroyed.
  func dispose()
  func resize(_ size: CGSize)
  func render(_ size: CGSize)
}
