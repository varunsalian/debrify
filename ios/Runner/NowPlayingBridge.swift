import AVFoundation
import Flutter
import MediaPlayer

/// Lock screen, Control Centre and headphone controls for the in-app player.
///
/// Dart pushes the playing item over `com.debrify.app/now_playing` ("update" with
/// NowPlayingInfo.toMap(), "clear"); remote commands come back as "command" with
/// {"type": ..., "positionMs": ...}. The system extrapolates the elapsed time
/// from the pushed position and rate, so Dart only pushes on changes.
final class NowPlayingBridge {
  private let channel: FlutterMethodChannel
  private var targets: [(MPRemoteCommand, Any)] = []
  private var sessionActive = false
  private var interruption: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.debrify.app/now_playing", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "update":
        self.update(call.arguments as? [String: Any] ?? [:])
        result(nil)
      case "clear":
        self.clear()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    // A call or another app's audio interrupts the session; activate it
    // again on the next update so the remote commands keep arriving.
    interruption = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { [weak self] _ in
      self?.sessionActive = false
    }
  }

  deinit {
    if let interruption { NotificationCenter.default.removeObserver(interruption) }
  }

  private func update(_ info: [String: Any]) {
    activateSession()
    installTargets()
    let live = info["isLive"] as? Bool ?? false
    let durationMs = (info["durationMs"] as? NSNumber)?.doubleValue ?? 0
    let positionMs = (info["positionMs"] as? NSNumber)?.doubleValue ?? 0
    let rate = (info["rate"] as? NSNumber)?.doubleValue ?? 0
    var now: [String: Any] = [
      MPMediaItemPropertyTitle: info["title"] as? String ?? "",
      MPNowPlayingInfoPropertyElapsedPlaybackTime: positionMs / 1000,
      MPNowPlayingInfoPropertyPlaybackRate: rate,
      MPNowPlayingInfoPropertyIsLiveStream: live,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
    ]
    if let subtitle = info["subtitle"] as? String, !subtitle.isEmpty {
      now[MPMediaItemPropertyArtist] = subtitle
    }
    if !live && durationMs > 0 {
      now[MPMediaItemPropertyPlaybackDuration] = durationMs / 1000
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = now
    let center = MPRemoteCommandCenter.shared()
    let seekable = !live && durationMs > 0
    center.skipForwardCommand.isEnabled = seekable
    center.skipBackwardCommand.isEnabled = seekable
    center.changePlaybackPositionCommand.isEnabled = seekable
    center.nextTrackCommand.isEnabled = info["canGoNext"] as? Bool ?? false
    center.previousTrackCommand.isEnabled = info["canGoPrevious"] as? Bool ?? false
  }

  private func clear() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    for (command, target) in targets {
      command.removeTarget(target)
    }
    targets.removeAll()
    // Hand audio back: other apps resume, and the rest of the app (trailers)
    // returns to the default category that respects the silent switch. A
    // player parked in PiP never clears, so this never cuts it off.
    if sessionActive {
      let session = AVAudioSession.sharedInstance()
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
      try? session.setCategory(.soloAmbient)
      sessionActive = false
    }
  }

  private func activateSession() {
    guard !sessionActive else { return }
    // Remote commands and AirPods only reach an app whose session plays audio.
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    try? AVAudioSession.sharedInstance().setActive(true)
    sessionActive = true
  }

  private func installTargets() {
    guard targets.isEmpty else { return }
    let center = MPRemoteCommandCenter.shared()
    center.skipForwardCommand.preferredIntervals = [15]
    center.skipBackwardCommand.preferredIntervals = [15]
    add(center.playCommand, "play")
    add(center.pauseCommand, "pause")
    add(center.togglePlayPauseCommand, "toggle")
    add(center.skipForwardCommand, "skipForward")
    add(center.skipBackwardCommand, "skipBackward")
    add(center.nextTrackCommand, "next")
    add(center.previousTrackCommand, "previous")
    let seek = center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      self.send("seekTo", positionMs: Int(event.positionTime * 1000))
      return .success
    }
    targets.append((center.changePlaybackPositionCommand, seek))
  }

  private func add(_ command: MPRemoteCommand, _ type: String) {
    command.isEnabled = true
    let target = command.addTarget { [weak self] _ in
      self?.send(type)
      return .success
    }
    targets.append((command, target))
  }

  private func send(_ type: String, positionMs: Int? = nil) {
    var args: [String: Any] = ["type": type]
    if let positionMs { args["positionMs"] = max(0, positionMs) }
    channel.invokeMethod("command", arguments: args)
  }
}
