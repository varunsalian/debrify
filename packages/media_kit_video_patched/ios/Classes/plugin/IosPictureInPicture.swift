import AVKit
import Flutter
import UIKit

/// AVKit owns presentation; the existing mpv player remains the playback owner.
/// Manual entry deliberately prepares a non-OpenGL renderer before backgrounding.
@available(iOS 15.0, *)
final class IosPictureInPicture: NSObject, AVPictureInPictureControllerDelegate,
  AVPictureInPictureSampleBufferPlaybackDelegate {
  private let channel: FlutterMethodChannel
  private let outputs: VideoOutputManager
  private var controller: AVPictureInPictureController?
  private var sourceView: UIView?
  private var displayLayer: AVSampleBufferDisplayLayer?
  private var observation: NSKeyValueObservation?
  private var output: VideoOutput?
  private var handle: Int64?
  private var generation = 0
  private var starting = false
  private var prepared = false
  private var hasFrame = false
  private var restoring = false
  private var playing = false
  private var duration = 0.0
  private var position = 0.0
  private var pendingResult: FlutterResult?
  private var foregroundObserver: NSObjectProtocol?
  // The output worker may produce faster than the main thread can consume.
  private let frameLock = NSLock()
  private var frameQueued = false

  init(messenger: FlutterBinaryMessenger, outputs: VideoOutputManager) {
    self.channel = FlutterMethodChannel(name: "com.debrify.app/pip", binaryMessenger: messenger)
    self.outputs = outputs
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleCall(call, result: result)
    }
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self = self, self.controller == nil else { return }
      self.restoreRenderer()
    }
  }

  private func handleCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "isSupported":
      result(AVPictureInPictureController.isPictureInPictureSupported())
    case "enterPip":
      guard let raw = args["playerHandle"] as? String, let handle = Int64(raw) else {
        result(false); return
      }
      start(handle: handle, result: result)
    case "updatePlaybackState":
      playing = args["isPlaying"] as? Bool ?? false
      position = (args["positionMs"] as? NSNumber)?.doubleValue ?? 0
      position /= 1000
      duration = (args["durationMs"] as? NSNumber)?.doubleValue ?? 0
      duration /= 1000
      if let timebase = displayLayer?.controlTimebase {
        CMTimebaseSetTime(timebase, time: CMTime(seconds: position, preferredTimescale: 600))
        CMTimebaseSetRate(timebase, rate: playing ? 1 : 0)
      }
      controller?.invalidatePlaybackState()
      result(nil)
    case "setAutoEnter":
      // Android auto-entry is activity based. iOS must prepare its renderer
      // while foregrounded, so it enters only through the explicit PiP button.
      result(nil)
    case "detach":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(handle: Int64, result: @escaping FlutterResult) {
    guard controller == nil, !starting,
          UIApplication.shared.applicationState == .active,
          let output = outputs.output(for: handle),
          let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else {
      result(false); return
    }
    restoreRenderer()
    generation += 1
    let request = generation
    self.handle = handle
    self.output = output
    starting = true
    prepared = false
    hasFrame = false
    restoring = false
    pendingResult = result

    // A real, attached video source is required for AVKit's possibility checks
    // and fullscreen restoration animation. Flutter remains in front of it.
    let view = UIView(frame: window.bounds)
    view.isUserInteractionEnabled = false
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.insertSubview(view, at: 0)
    let layer = AVSampleBufferDisplayLayer()
    layer.frame = view.bounds
    layer.videoGravity = .resizeAspect
    view.layer.addSublayer(layer)
    var timebase: CMTimebase?
    CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
      sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
    layer.controlTimebase = timebase
    if let timebase = timebase {
      CMTimebaseSetTime(timebase, time: CMTime(seconds: position, preferredTimescale: 600))
      CMTimebaseSetRate(timebase, rate: playing ? 1 : 0)
    }
    sourceView = view
    displayLayer = layer
    let controller = AVPictureInPictureController(contentSource:
      .init(sampleBufferDisplayLayer: layer, playbackDelegate: self))
    self.controller = controller
    controller.delegate = self
    controller.canStartPictureInPictureAutomaticallyFromInline = false

    do {
      let audio = AVAudioSession.sharedInstance()
      try audio.setCategory(.playback, mode: .moviePlayback)
      try audio.setActive(true)
    } catch {
      finish(success: false)
      return
    }
    output.preparePip(frame: { [weak self] buffer in
      self?.queueFrame(buffer, generation: request)
    }) { [weak self] prepared in
      guard let self = self, request == self.generation else { return }
      guard prepared, UIApplication.shared.applicationState == .active else {
        self.finish(success: false); return
      }
      self.prepared = true
      self.observation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) {
        [weak self] controller, _ in
        DispatchQueue.main.async {
          guard let self = self, self.generation == request else { return }
          self.startIfReady()
        }
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
        guard let self = self, request == self.generation,
              self.pendingResult != nil else { return }
        self.stop()
      }
    }
  }

  // Called on the rendering worker. Copy into an owned buffer: mpv recycles
  // its three texture buffers even while AVKit still holds a submitted frame.
  private func queueFrame(_ source: CVPixelBuffer, generation: Int) {
    frameLock.lock()
    if frameQueued { frameLock.unlock(); return }
    frameQueued = true
    frameLock.unlock()
    let copy = PipPixelBuffer.copyForDisplay(source)
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      defer {
        self.frameLock.lock()
        self.frameQueued = false
        self.frameLock.unlock()
      }
      guard generation == self.generation, let copy = copy,
            let layer = self.displayLayer else { return }
      if layer.status == .failed { layer.flush() }
      guard layer.isReadyForMoreMediaData else { return }
      var format: CMVideoFormatDescription?
      guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
        imageBuffer: copy, formatDescriptionOut: &format) == noErr, let format = format else { return }
      var timing = CMSampleTimingInfo(duration: .invalid,
        presentationTimeStamp: CMTime(seconds: self.position, preferredTimescale: 600),
        decodeTimeStamp: .invalid)
      var sample: CMSampleBuffer?
      guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
        imageBuffer: copy, formatDescription: format, sampleTiming: &timing,
        sampleBufferOut: &sample) == noErr, let sample = sample else { return }
      if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(dictionary,
          Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
          Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
      }
      layer.enqueue(sample)
      self.hasFrame = true
      self.startIfReady()
    }
  }

  private func startIfReady() {
    guard starting, prepared, hasFrame, let controller = controller,
          controller.isPictureInPicturePossible else { return }
    observation = nil
    starting = false
    controller.startPictureInPicture()
  }

  func disposeOutput(handle: Int64) {
    if self.handle == handle {
      stop()
      // The manager now owns disposal; never restore its renderer later.
      output = nil
      self.handle = nil
    }
  }

  private func stop() {
    if controller?.isPictureInPictureActive == true {
      controller?.stopPictureInPicture()
    } else {
      finish(success: false)
    }
  }

  private func restoreRenderer() {
    guard UIApplication.shared.applicationState == .active else { return }
    output?.finishPip()
    output = nil
    handle = nil
  }

  private func emit(_ method: String, _ value: Any) {
    channel.invokeMethod(method, arguments: ["playerHandle": handle.map(String.init) ?? "", "value": value])
  }

  private func finish(success: Bool) {
    generation += 1
    output?.stopPipFrames()
    starting = false
    observation = nil
    controller?.delegate = nil
    controller = nil
    displayLayer?.flushAndRemoveImage()
    displayLayer = nil
    sourceView?.removeFromSuperview()
    sourceView = nil
    pendingResult?(success)
    pendingResult = nil
    emit("onPipModeChanged", false)
    restoreRenderer()
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
    guard controller === self.controller else { return }
    pendingResult?(true)
    pendingResult = nil
    emit("onPipModeChanged", true)
  }

  func pictureInPictureController(_ controller: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error) {
    guard controller === self.controller else { return }
    NSLog("iOS PiP failed to start: \(error)")
    finish(success: false)
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
    guard controller === self.controller else { return }
    // Closing the PiP window means stop playback; fullscreen restoration does not.
    if !restoring { emit("onPipAction", "pause") }
    finish(success: false)
  }

  func pictureInPictureController(_ controller: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
    guard controller === self.controller else { completionHandler(false); return }
    restoring = true
    channel.invokeMethod("onPipRestore", arguments: [
      "playerHandle": handle.map(String.init) ?? "", "value": true
    ]) { [weak self] result in
      guard let self = self, controller === self.controller else {
        completionHandler(false); return
      }
      let restored = (result as? Bool == true) && self.output != nil
      self.restoring = restored
      completionHandler(restored)
    }
  }

  func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
    guard controller === self.controller else { return }
    emit("onPipAction", playing ? "play" : "pause")
  }

  func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
    !playing
  }

  func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
    if duration <= 0 { return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity) }
    return CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
  }

  func pictureInPictureController(_ controller: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

  func pictureInPictureController(_ controller: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
    guard duration > 0 else { completionHandler(); return }
    channel.invokeMethod("onPipAction", arguments: ["playerHandle": handle.map(String.init) ?? "", "value": "seek:\(skipInterval.seconds)"]) { _ in
      completionHandler()
    }
  }

  deinit {
    if let observer = foregroundObserver { NotificationCenter.default.removeObserver(observer) }
  }
}
