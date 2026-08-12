import UIKit
import Flutter
import TVServices
import AVFoundation

private enum TopShelfPreviewError: LocalizedError {
    case invalidArguments
    case appGroupUnavailable
    case noVideoTrack
    case invalidDuration
    case compositionFailed
    case exportUnavailable
    case exportFailed
    case outputInvalid

    var errorDescription: String? {
        switch self {
        case .invalidArguments: return "The preview request is invalid."
        case .appGroupUnavailable: return "The Top Shelf App Group is unavailable."
        case .noVideoTrack: return "The trailer has no usable video track."
        case .invalidDuration: return "The trailer duration is invalid."
        case .compositionFailed: return "The trailer tracks could not be combined."
        case .exportUnavailable: return "The trailer cannot be exported as an MP4."
        case .exportFailed: return "The trailer export failed."
        case .outputInvalid: return "The cached trailer file is invalid."
        }
    }
}

@main
class AppDelegate: FlutterAppDelegate {
    /// Retained so the channel outlives `application(_:didFinishLaunchingWithOptions:)`.
    private var logChannel: FlutterMethodChannel?
    private var keyboardChannel: FlutterMethodChannel?
    private var urlChannel: FlutterMethodChannel?
    private var systemChannel: FlutterMethodChannel?
    private var topShelfChannel: FlutterMethodChannel?
    private var pendingTopShelfAction: [String: String]?

    private static let topShelfAppGroup = "group.com.varunsalian.debrifytv"
    private static let topShelfSnapshotPath = "Library/Caches/top-shelf-v1.json"
    private static let topShelfPreviewDirectory = "Library/Caches/TopShelfPreviews"
    private static let topShelfPreviewMaxAge: TimeInterval = 14 * 24 * 60 * 60
    private static let topShelfPreviewMaxFiles = 6
    private static let topShelfPreviewMaxBytes: Int64 = 180 * 1024 * 1024

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let flutterViewController = FlutterViewController(project: nil, nibName: nil, bundle: nil)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = flutterViewController
        window.makeKeyAndVisible()
        self.window = window

        // tvOS reports a screen scale of 1.0, so Flutter lays out against a
        // 1920x1080 LOGICAL canvas. Android TV reports 2.0 for the same panel —
        // a 960x540 logical canvas — and every size in this app (type scale,
        // padding, card and row dimensions, focus rings) was designed against
        // that. Left at 1.0 the whole UI renders at half its intended physical
        // size: readable on a monitor at desk distance, unreadable from a sofa.
        //
        // Raising the view's contentScaleFactor makes the engine lay out
        // against 960x540 while still rasterising into the full 1920x1080
        // surface, so this costs no sharpness — same pixels, correct sizes.
        flutterViewController.view.contentScaleFactor = 2.0

        // Dart's print()/debugPrint() goes to stdout, which the device console
        // does not carry in a release build — so on real hardware every Dart
        // error, including the framework's own, is invisible. Bridge it to
        // NSLog, which `devicectl ... --console` does capture. Dart side opts in
        // (tvOS only) by reassigning debugPrint.
        let logChannel = FlutterMethodChannel(
            name: "debrify/tvlog",
            binaryMessenger: flutterViewController.binaryMessenger)
        logChannel.setMethodCallHandler { call, result in
            if call.method == "log", let message = call.arguments as? String {
                NSLog("[dart] %@", message)
            }
            result(nil)
        }
        self.logChannel = logChannel

        GeneratedPluginRegistrant.register(with: self)

        // External player launch. url_launcher has no tvOS implementation in
        // this fork, and porting it for two UIApplication calls would be the
        // long way round — the Dart side (ExternalPlayerService._TvosUrl)
        // opens Infuse/VLC through this instead. `canOpen` answers honestly
        // only for schemes listed in LSApplicationQueriesSchemes; `open`
        // reports whether tvOS accepted the launch.
        let urlChannel = FlutterMethodChannel(
            name: "debrify/tvurl",
            binaryMessenger: flutterViewController.binaryMessenger)
        urlChannel.setMethodCallHandler { call, result in
            guard let urlString = call.arguments as? String,
                  let url = URL(string: urlString) else {
                result(false)
                return
            }
            switch call.method {
            case "canOpen":
                result(UIApplication.shared.canOpenURL(url))
            case "open":
                UIApplication.shared.open(url, options: [:]) { ok in
                    result(ok)
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        self.urlChannel = urlChannel

        // Menu at the app's true root must land the user on the tvOS Home
        // Screen — but Flutter's unhandled-pop fallback (SystemNavigator.pop)
        // is a no-op here: its Darwin implementation only pops a navigation
        // controller, and this app installs the FlutterViewController as the
        // window root. UIKit's `suspend` selector does exactly what the TV
        // button does — the scene resigns and tvOS takes over. (Private
        // selector; this is a sideloaded app, App Store review is not a
        // constraint.)
        let systemChannel = FlutterMethodChannel(
            name: "debrify/tvsystem",
            binaryMessenger: flutterViewController.binaryMessenger)
        systemChannel.setMethodCallHandler { call, result in
            if call.method == "suspend" {
                DispatchQueue.main.async {
                    // Suspend first so the system's zoom-out to the Home
                    // Screen plays; then actually terminate, so the next
                    // launch is a cold start (boot ident and all) instead of
                    // a warm resume. exit() alone looks like a crash — the
                    // app vanishes with no animation.
                    UIApplication.shared.perform(Selector(("suspend")))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        exit(0)
                    }
                }
                result(true)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
        self.systemChannel = systemChannel

        // Top Shelf is a separate, low-memory TVServices extension. Flutter
        // writes only a bounded JSON snapshot into the shared App Group; the
        // extension can then render while this app is not running. In the
        // opposite direction, a Top Shelf URL is reduced to metadata and
        // handed to Dart so the existing detail-page route remains the single
        // source of navigation truth.
        let topShelfChannel = FlutterMethodChannel(
            name: "debrify/topshelf",
            binaryMessenger: flutterViewController.binaryMessenger)
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.topShelfAppGroup) {
            let previewDirectory = container.appendingPathComponent(
                Self.topShelfPreviewDirectory,
                isDirectory: true)
            pruneTopShelfPreviews(in: previewDirectory, preserving: nil)
            NSLog("[TopShelf] App Group ready: %@", container.path)
        } else {
            NSLog("[TopShelf] App Group unavailable at launch")
        }
        topShelfChannel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(FlutterError(code: "unavailable", message: nil, details: nil))
                return
            }
            switch call.method {
            case "publish":
                guard let json = call.arguments as? String,
                      let data = json.data(using: .utf8),
                      data.count <= 512 * 1024 else {
                    result(FlutterError(
                        code: "invalid_snapshot",
                        message: "Top Shelf snapshot is missing or too large.",
                        details: nil))
                    return
                }
                do {
                    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          root["version"] as? Int == 1,
                          root["items"] is [[String: Any]] else {
                        result(FlutterError(
                            code: "invalid_snapshot",
                            message: "Top Shelf snapshot has an unsupported shape.",
                            details: nil))
                        return
                    }
                    guard let container = FileManager.default.containerURL(
                        forSecurityApplicationGroupIdentifier: Self.topShelfAppGroup) else {
                        NSLog("[TopShelf] Publish rejected: App Group unavailable")
                        result(FlutterError(
                            code: "app_group_unavailable",
                            message: "The Top Shelf App Group is unavailable.",
                            details: nil))
                        return
                    }
                    let destination = container.appendingPathComponent(Self.topShelfSnapshotPath)
                    try data.write(to: destination, options: .atomic)
                    let itemCount = (root["items"] as? [[String: Any]])?.count ?? 0
                    NSLog("[TopShelf] Published %ld item(s)", itemCount)
                    TVTopShelfContentProvider.topShelfContentDidChange()
                    result(nil)
                } catch {
                    NSLog("[TopShelf] Publish failed: %@", error.localizedDescription)
                    result(FlutterError(
                        code: "snapshot_write_failed",
                        message: error.localizedDescription,
                        details: nil))
                }
            case "cachePreview":
                guard let arguments = call.arguments as? [String: Any] else {
                    result(FlutterError(
                        code: "invalid_preview",
                        message: TopShelfPreviewError.invalidArguments.localizedDescription,
                        details: nil))
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self else {
                        result(FlutterError(code: "unavailable", message: nil, details: nil))
                        return
                    }
                    do {
                        let path = try await self.cacheTopShelfPreview(arguments)
                        result(path)
                    } catch {
                        NSLog("[TopShelf] Preview cache failed: %@", error.localizedDescription)
                        result(FlutterError(
                            code: "preview_cache_failed",
                            message: error.localizedDescription,
                            details: nil))
                    }
                }
            case "takePendingAction":
                NSLog("[TopShelf] Flutter channel connected")
                let action = self.pendingTopShelfAction
                self.pendingTopShelfAction = nil
                result(action)
            case "clearPendingAction":
                if let acknowledged = call.arguments as? [String: String],
                   self.pendingTopShelfAction == acknowledged {
                    self.pendingTopShelfAction = nil
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        self.topShelfChannel = topShelfChannel

        if let launchURL = launchOptions?[.url] as? URL,
           let action = topShelfAction(from: launchURL) {
            pendingTopShelfAction = action
        }

        // Apple TV's keyboard never tells Flutter the user finished.
        //
        // The engine raises a submit action from exactly one place — when the
        // platform inserts a literal "\n" (FlutterTextInputPlugin.mm,
        // -shouldChangeTextInRange:replacementText:). That is the iOS inline
        // keyboard's contract. tvOS presents a full-screen keyboard whose
        // action button commits and dismisses WITHOUT inserting anything, so
        // the trigger never fires and `onSubmitted` never runs: every text
        // field on the platform is a dead end.
        //
        // UIKit does post the fact, though — verified on an Apple TV 4K
        // (tvOS 26.6): pressing the action key emits exactly one
        // UITextFieldTextDidEndEditingNotification, and typing emits none.
        // Bridge it to Dart, which treats it as "editing finished".
        //
        // Caveat, measured rather than assumed: dismissing with the remote's
        // BACK button emits the SAME notification, so commit and cancel are
        // indistinguishable here. Dart side decides what that's worth.
        let keyboardChannel = FlutterMethodChannel(
            name: "debrify/tvkeyboard",
            binaryMessenger: flutterViewController.binaryMessenger)
        self.keyboardChannel = keyboardChannel
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UITextFieldTextDidEndEditingNotification"),
            object: nil,
            queue: .main
        ) { [weak keyboardChannel] _ in
            keyboardChannel?.invokeMethod("endEditing", arguments: nil)
        }


        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard let action = topShelfAction(from: url) else {
            return super.application(app, open: url, options: options)
        }
        pendingTopShelfAction = action
        topShelfChannel?.invokeMethod("action", arguments: action)
        return true
    }

    private func topShelfAction(from url: URL) -> [String: String]? {
        guard url.scheme?.lowercased() == "debrify",
              url.host?.lowercased() == "topshelf",
              url.path == "/display",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var values: [String: String] = [:]
        let allowed = Set(["imdbId", "type", "title", "posterURL", "year"])
        for item in components.queryItems ?? [] where allowed.contains(item.name) {
            if let value = item.value, value.count <= 2_048 {
                values[item.name] = value
            }
        }
        guard let imdbID = values["imdbId"],
              imdbID.range(of: #"^tt\d{7,10}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return values
    }

    /// Downloads and remuxes a bounded trailer clip while the full app is
    /// running. The Top Shelf extension never performs this work: it receives
    /// only the relative path of the finished MP4 in the shared App Group.
    @MainActor
    private func cacheTopShelfPreview(_ arguments: [String: Any]) async throws -> String {
        guard let cacheKey = arguments["cacheKey"] as? String,
              cacheKey.count <= 96,
              cacheKey.range(
                of: #"^[A-Za-z0-9._-]+$"#,
                options: .regularExpression) != nil,
              let videoString = arguments["videoURL"] as? String,
              let videoURL = validatedTopShelfMediaURL(videoString) else {
            throw TopShelfPreviewError.invalidArguments
        }
        let includeAudio = arguments["includeAudio"] as? Bool ?? true
        let audioURL = (arguments["audioURL"] as? String).flatMap(validatedTopShelfMediaURL)
        let requestedDuration = (arguments["maxDurationSeconds"] as? NSNumber)?.doubleValue ?? 90
        let maxDuration = min(max(requestedDuration, 15), 120)

        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.topShelfAppGroup) else {
            throw TopShelfPreviewError.appGroupUnavailable
        }
        let previewDirectory = container.appendingPathComponent(
            Self.topShelfPreviewDirectory,
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: previewDirectory,
            withIntermediateDirectories: true)
        let fileName = "\(cacheKey).mp4"
        let destination = previewDirectory.appendingPathComponent(fileName)
        let relativePath = "\(Self.topShelfPreviewDirectory)/\(fileName)"

        if isFreshTopShelfPreview(destination) {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: destination.path)
            pruneTopShelfPreviews(in: previewDirectory, preserving: destination)
            NSLog("[TopShelf] Reused cached preview")
            return relativePath
        }

        let videoAsset = AVURLAsset(url: videoURL)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw TopShelfPreviewError.noVideoTrack
        }
        let sourceDuration = try await videoAsset.load(.duration)
        guard sourceDuration.isValid,
              !sourceDuration.isIndefinite,
              sourceDuration.seconds.isFinite,
              sourceDuration.seconds > 1 else {
            throw TopShelfPreviewError.invalidDuration
        }
        let durationLimit = CMTime(seconds: maxDuration, preferredTimescale: 600)
        let clipDuration = CMTimeCompare(sourceDuration, durationLimit) > 0
            ? durationLimit
            : sourceDuration

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw TopShelfPreviewError.compositionFailed
        }
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: clipDuration),
            of: sourceVideoTrack,
            at: .zero)
        if let transform = try? await sourceVideoTrack.load(.preferredTransform) {
            compositionVideoTrack.preferredTransform = transform
        }

        if includeAudio {
            do {
                let sourceAudioAsset = audioURL.map(AVURLAsset.init(url:)) ?? videoAsset
                let audioTracks = try await sourceAudioAsset.loadTracks(withMediaType: .audio)
                if let sourceAudioTrack = audioTracks.first {
                    let audioDuration = try await sourceAudioAsset.load(.duration)
                    if audioDuration.isValid,
                       !audioDuration.isIndefinite,
                       audioDuration.seconds.isFinite,
                       audioDuration.seconds > 0,
                       let compositionAudioTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid) {
                        let usableAudioDuration = CMTimeCompare(audioDuration, clipDuration) < 0
                            ? audioDuration
                            : clipDuration
                        try compositionAudioTrack.insertTimeRange(
                            CMTimeRange(start: .zero, duration: usableAudioDuration),
                            of: sourceAudioTrack,
                            at: .zero)
                    }
                }
            } catch {
                // A restricted/missing audio rendition should degrade to a
                // silent preview, not discard a perfectly usable video track.
                NSLog("[TopShelf] Preview audio unavailable; caching video only")
            }
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough),
              exporter.supportedFileTypes.contains(.mp4) else {
            throw TopShelfPreviewError.exportUnavailable
        }
        let temporary = previewDirectory.appendingPathComponent(
            ".\(cacheKey)-\(UUID().uuidString).partial.mp4")
        try? FileManager.default.removeItem(at: temporary)
        exporter.outputURL = temporary
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        do {
            try await exportTopShelfPreview(exporter)
            let attributes = try FileManager.default.attributesOfItem(atPath: temporary.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard size >= 256 * 1024 else {
                throw TopShelfPreviewError.outputInvalid
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(
                    destination,
                    withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            pruneTopShelfPreviews(in: previewDirectory, preserving: destination)
            NSLog("[TopShelf] Cached preview (%ld bytes)", size)
            return relativePath
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func validatedTopShelfMediaURL(_ raw: String) -> URL? {
        guard raw.count <= 16_384,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private func isFreshTopShelfPreview(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value >= 256 * 1024,
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < Self.topShelfPreviewMaxAge else {
            return false
        }
        return true
    }

    private func exportTopShelfPreview(_ exporter: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exporter.error ?? TopShelfPreviewError.exportFailed)
                default:
                    continuation.resume(throwing: TopShelfPreviewError.exportFailed)
                }
            }
        }
    }

    private func pruneTopShelfPreviews(in directory: URL, preserving: URL?) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: []) else {
            return
        }
        let now = Date()
        var candidates: [(url: URL, modified: Date, size: Int64)] = []
        for file in files where file.pathExtension.lowercased() == "mp4" {
            guard let values = try? file.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                continue
            }
            let modified = values.contentModificationDate ?? .distantPast
            if file.lastPathComponent.hasPrefix(".") {
                if now.timeIntervalSince(modified) >= 60 * 60 {
                    try? manager.removeItem(at: file)
                }
                continue
            }
            let mustPreserve = preserving == file
            if !mustPreserve && now.timeIntervalSince(modified) >= Self.topShelfPreviewMaxAge {
                try? manager.removeItem(at: file)
                continue
            }
            candidates.append((file, modified, Int64(values.fileSize ?? 0)))
        }
        candidates.sort { $0.modified > $1.modified }
        var keptCount = 0
        var keptBytes: Int64 = 0
        for candidate in candidates {
            let canKeep = candidate.url == preserving ||
                (keptCount < Self.topShelfPreviewMaxFiles &&
                 keptBytes + candidate.size <= Self.topShelfPreviewMaxBytes)
            if canKeep {
                keptCount += 1
                keptBytes += candidate.size
            } else {
                try? manager.removeItem(at: candidate.url)
            }
        }
    }
}
