#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

// This class avoids data race when called from a thread
public class SafeResizableTexture:
  NSObject,
  FlutterTexture,
  ResizableTextureProtocol
{
  private let lock = NSRecursiveLock()
  private var child: ResizableTextureProtocol

  init(_ child: ResizableTextureProtocol) {
    self.child = child
  }

  /// Keep Flutter's registered texture stable while changing the mpv renderer.
  public func replace(with makeChild: () -> ResizableTextureProtocol) {
    locked {
      child.dispose()
      child = makeChild()
    }
  }

  public func dispose() {
    locked { child.dispose() }
  }

  public func resize(_ size: CGSize) {
    return locked {
      return child.resize(size)
    }
  }

  public func render(_ size: CGSize) {
    return locked {
      return child.render(size)
    }
  }

  public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    return locked { child.copyPixelBuffer() }
  }

  private func locked<T>(do block: () -> T) -> T {
    lock.lock()
    defer {
      lock.unlock()
    }

    return block()
  }
}
