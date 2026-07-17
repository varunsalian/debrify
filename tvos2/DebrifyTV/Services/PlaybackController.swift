import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class PlaybackController {
    private let persistence: PersistenceStore
    private var timeObserver: Any?
    private(set) var player = AVPlayer()
    private(set) var currentItem: MediaItem?
    private(set) var currentSource: StreamSource?
    var position: Double = 0
    var duration: Double = 0
    var isPlaying = false

    init(persistence: PersistenceStore) { self.persistence = persistence }

    func load(item: MediaItem, source: StreamSource) {
        stop()
        currentItem = item
        currentSource = source
        let options: [String: Any]? = source.headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": source.headers]
        let asset = AVURLAsset(url: source.url, options: options)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)
        installTimeObserver()
        if item.progressSeconds > 0 {
            player.seek(to: CMTime(seconds: item.progressSeconds, preferredTimescale: 600))
        }
        player.play()
        isPlaying = true
    }

    func toggle() {
        if player.timeControlStatus == .playing { player.pause(); isPlaying = false }
        else { player.play(); isPlaying = true }
    }

    func seek(by seconds: Double) {
        let target = max(0, min(position + seconds, duration > 0 ? duration : .greatestFiniteMagnitude))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func stop() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        isPlaying = false
    }

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 2), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
                let rawDuration = self.player.currentItem?.duration.seconds ?? 0
                self.duration = rawDuration.isFinite ? rawDuration : 0
            }
        }
    }
}
