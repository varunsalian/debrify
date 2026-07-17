import Foundation
import UIKit

@MainActor
final class InfuseLauncher {
    nonisolated static func playbackURL(item: MediaItem, source: StreamSource) -> URL? {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard
            let encodedURL = source.url.absoluteString.addingPercentEncoding(withAllowedCharacters: unreserved),
            let encodedFilename = item.title.addingPercentEncoding(withAllowedCharacters: unreserved)
        else { return nil }

        var components = URLComponents()
        components.scheme = "infuse"
        components.host = "x-callback-url"
        components.path = "/play"
        components.percentEncodedQuery = "url=\(encodedURL)&filename=\(encodedFilename)"
        return components.url
    }

    func open(item: MediaItem, source: StreamSource) async -> Bool {
        guard let url = Self.playbackURL(item: item, source: source) else { return false }
        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { opened in
                continuation.resume(returning: opened)
            }
        }
    }
}
