#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

// This class creates and manipulates the different types of FlutterTexture,
// handles resizing, rendering calls, and notify Flutter when a new frame is
// available to render.
//
// To improve the user experience, a worker is used to execute heavy tasks on a
// dedicated thread.
public class VideoOutput: NSObject {
  // Will be called on the main thread
  public typealias TextureUpdateCallback = (Int64, CGSize) -> Void

  private static let isSimulator: Bool = {
    let isSim: Bool
    #if targetEnvironment(simulator)
      isSim = true
    #else
      isSim = false
    #endif
    return isSim
  }()

  private let handle: OpaquePointer
  private let enableHardwareAcceleration: Bool
  private let registry: FlutterTextureRegistry
  private let textureUpdateCallback: TextureUpdateCallback
  private let worker: Worker = .init()
  private var width: Int64?
  private var height: Int64?
  private var texture: ResizableTextureProtocol!
  private var textureId: Int64 = -1
  private var currentSize: CGSize = CGSize.zero
  // Written on the platform thread (dispose) and read on the worker
  // (_updateCallback); every access goes through the lock.
  private let disposedLock = NSLock()
  private var disposed: Bool = false

  private var isDisposed: Bool {
    disposedLock.lock()
    defer { disposedLock.unlock() }
    return disposed
  }

  // Returns true only for the first caller; later callers see false.
  private func markDisposed() -> Bool {
    disposedLock.lock()
    defer { disposedLock.unlock() }
    if disposed {
      return false
    }
    disposed = true
    return true
  }

  init(
    handle: Int64,
    configuration: VideoOutputConfiguration,
    registry: FlutterTextureRegistry,
    textureUpdateCallback: @escaping TextureUpdateCallback
  ) {
    let handle = OpaquePointer(bitPattern: Int(handle))
    assert(handle != nil, "handle casting")

    self.handle = handle!
    width = configuration.width
    height = configuration.height
    enableHardwareAcceleration = configuration.enableHardwareAcceleration
    self.registry = registry
    self.textureUpdateCallback = textureUpdateCallback

    super.init()

    worker.enqueue {
      self._init()
    }
  }

  deinit {
    worker.cancel()

    // Fallback for outputs never disposed through the method channel. The
    // texture's render context is freed here synchronously; freeing it lazily
    // in the texture's own deinit (raster thread) races mpv core teardown.
    if markDisposed() {
      texture?.dispose()
    }
    disposeTextureId()
  }

  // Frees the mpv render context, then unregisters the texture and calls
  // `completion`. The platform Dispose call must not return to Dart before the
  // render context is gone: mpv requires `mpv_render_context_free` strictly
  // before `mpv_terminate_destroy`, and Dart terminates the core as soon as
  // the Dispose call completes.
  public func dispose(completion: @escaping () -> Void) {
    if !markDisposed() {
      // A disposal is already queued or done. Worker FIFO ordering runs this
      // job after the dispose job, so the completion still fires only once
      // the render context is actually gone — never early. Retaining self
      // keeps deinit's worker.cancel() from dropping this job (and the
      // completion with it) before it runs.
      worker.enqueue {
        withExtendedLifetime(self) {}
        DispatchQueue.main.async {
          completion()
        }
      }
      return
    }

    // Run on the worker so this is ordered after `_init` (which creates the
    // texture) and after any in-flight render.
    worker.enqueue {
      self.texture?.dispose()
      DispatchQueue.main.async {
        self.disposeTextureId()
        completion()
      }
    }
  }

  public func setSize(width: Int64?, height: Int64?) {
    worker.enqueue {
      self.width = width
      self.height = height
    }
  }

  private func _init() {
    let enableHardwareAcceleration =
      VideoOutput.isSimulator ? false : enableHardwareAcceleration

    NSLog(
      "VideoOutput: enableHardwareAcceleration: \(enableHardwareAcceleration)"
    )

    if VideoOutput.isSimulator {
      NSLog(
        "VideoOutput: warning: hardware rendering is disabled in the iOS simulator, due to an incompatibility with OpenGL ES"
      )
    }

    if enableHardwareAcceleration {
      texture = SafeResizableTexture(
        TextureHW(
          handle: handle,
          // Use `weak self` to prevent memory leaks
          updateCallback: { [weak self]() in
            guard let that = self else {
              return
            }
            that.updateCallback()
          }
        )
      )
    } else {
      texture = SafeResizableTexture(
        TextureSW(
          handle: handle,
          // Use `weak self` to prevent memory leaks
          updateCallback: { [weak self]() in
            guard let that = self else {
              return
            }
            that.updateCallback()
          }
        )
      )
    }

    DispatchQueue.main.sync { [weak self]() in
      guard let that = self else {
        return
      }
      that.registerTextureId()
    }
  }

  // Must be run on the main thread
  private func registerTextureId() {
    // Textures must be registered on the platform thread.
    textureId = registry.register(texture)
    // textureUpdateCallback must run on the main thread
    textureUpdateCallback(textureId, CGSize(width: 0, height: 0))
  }

  private func disposeTextureId() {
    let registry_ = self.registry
    let textureId_ = self.textureId
    if textureId_ == -1 {
      return
    }
    textureId = -1
    DispatchQueue.main.async {
      // Textures must be unregistered on the platform thread
      registry_.unregisterTexture(textureId_)
    }
  }

  public func updateCallback() {
    worker.enqueue {
      self._updateCallback()
    }
  }

  private func _updateCallback() {
    // Jobs queued behind the dispose job run after the render context is freed
    // and Dart may already have terminated the mpv core; `videoSize` reads
    // core properties, so it must not run past disposal.
    if isDisposed {
      return
    }

    let size = videoSize

    if size.width == 0 || size.height == 0 {
      return
    }

    if currentSize != size {
      currentSize = size

      texture.resize(size)
      DispatchQueue.main.sync { [weak self] in
        guard let that = self else { return }
        // textureUpdateCallback must run on the main thread
        that.textureUpdateCallback(that.textureId, size)
      }
    }

    if isDisposed {
      return
    }

    texture.render(size)
    DispatchQueue.main.sync { [weak self] in
      guard let that = self else { return }
      // Textures must be marked as available from the main thread
      that.registry.textureFrameAvailable(that.textureId)
    }
  }

    private var videoSize: CGSize {
        // fixed size
        if width != nil && height != nil {
            return CGSize(
                width: Double(width!),
                height: Double(height!)
            )
        }
        
        let params = MPVHelpers.getVideoOutParams(handle)
        return CGSize(
            width: Double(width ?? (params.rotate == 0 || params.rotate == 180
                                    ? params.dw
                                    : params.dh)),
            height: Double(height ?? (params.rotate == 0 || params.rotate == 180
                                      ? params.dh
                                      : params.dw))
        )
  }
}
