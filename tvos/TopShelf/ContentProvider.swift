import Foundation
import TVServices

private enum TopShelfStore {
    static let appGroup = "group.com.varunsalian.debrifytv"
    static let snapshotPath = "Library/Caches/top-shelf-v1.json"
    static let actionsPath = "Library/Caches/top-shelf-actions-v1.json"
    static let previewDirectory = "Library/Caches/TopShelfPreviews/"
    static let previewMaxAge: TimeInterval = 14 * 24 * 60 * 60
}

private struct SpotlightSnapshot: Decodable {
    let version: Int
    let contextTitle: String
    let items: [SpotlightItem]
    let snapshotRevision: Int?
    let ownerProfileId: String?
    let profileAuthorizationRevision: Int?
}

private struct SpotlightItem: Decodable {
    let identifier: String
    let imdbId: String
    let type: String
    let title: String
    let imageURL: String
    let posterURL: String?
    let summary: String?
    let year: String?
    let rating: Double?
    let genres: [String]?
    let runtimeMinutes: Int?
    let previewFile: String?
    let actionToken: String?
}

private struct ActionDocument: Decodable {
    let version: Int
    let snapshotRevision: Int
    let actions: [String: ActionRecord]
}

private struct ActionRecord: Decodable {
    let ownerProfileId: String
    let expiresAtMs: Int64
    let consumed: Bool
    let profileAuthorizationRevision: Int
}

final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TopShelfStore.appGroup) else {
            return nil
        }
        let url = container.appendingPathComponent(TopShelfStore.snapshotPath)
        guard let data = try? Data(contentsOf: url),
              data.count <= 512 * 1024,
              let snapshot = try? JSONDecoder().decode(SpotlightSnapshot.self, from: data),
              [1, 2].contains(snapshot.version) else {
            return nil
        }
        let actionDocument: ActionDocument? = {
            guard snapshot.version == 2,
                  let revision = snapshot.snapshotRevision,
                  let actionData = try? Data(contentsOf: container.appendingPathComponent(TopShelfStore.actionsPath)),
                  let document = try? JSONDecoder().decode(ActionDocument.self, from: actionData),
                  document.version == 1,
                  document.snapshotRevision == revision else { return nil }
            return document
        }()
        if snapshot.version == 2 && actionDocument == nil { return nil }

        let items = snapshot.items.prefix(8).compactMap { source -> TVTopShelfCarouselItem? in
            guard let imageURL = validatedRemoteURL(source.imageURL),
                  let actionURL = actionURL(for: source, snapshot: snapshot, document: actionDocument) else {
                return nil
            }
            let item = TVTopShelfCarouselItem(identifier: source.identifier)
            // Carousel items have no separate `title` property. Put the
            // focused Spotlight title in the system's context line so a plain
            // backdrop (without baked-in logo art) is still identifiable.
            item.contextTitle = source.title
            item.summary = source.summary
            item.genre = source.genres?.prefix(2).joined(separator: " · ")
            if let minutes = source.runtimeMinutes, minutes > 0 {
                item.duration = TimeInterval(minutes * 60)
            }
            if let year = source.year,
               let date = releaseDate(for: year) {
                item.creationDate = date
            }
            var attributes: [TVTopShelfNamedAttribute] = []
            if let rating = source.rating, rating > 0 {
                attributes.append(TVTopShelfNamedAttribute(
                    name: "IMDb",
                    values: [String(format: "%.1f", rating)]))
            }
            item.namedAttributes = attributes
            item.setImageURL(imageURL, for: [.screenScale1x, .screenScale2x])
            if let previewURL = localPreviewURL(for: source, in: container) {
                item.previewVideoURL = previewURL
            }
            item.displayAction = TVTopShelfAction(url: actionURL)
            return item
        }
        guard !items.isEmpty else { return nil }
        return TVTopShelfCarouselContent(style: .details, items: items)
    }

    private func validatedRemoteURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }

    private func localPreviewURL(for item: SpotlightItem, in container: URL) -> URL? {
        guard let relativePath = item.previewFile,
              relativePath.count <= 180,
              relativePath.hasPrefix(TopShelfStore.previewDirectory),
              relativePath.range(
                of: #"^Library/Caches/TopShelfPreviews/[A-Za-z0-9._-]+\.mp4$"#,
                options: .regularExpression) != nil else {
            return nil
        }
        let url = container.appendingPathComponent(relativePath)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.int64Value >= 256 * 1024,
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < TopShelfStore.previewMaxAge else {
            return nil
        }
        return url
    }

    private func actionURL(
        for item: SpotlightItem,
        snapshot: SpotlightSnapshot,
        document: ActionDocument?
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "debrify"
        components.host = "topshelf"
        components.path = "/display"
        if snapshot.version == 2 {
            guard let token = item.actionToken,
                  token.range(of: #"^[A-Za-z0-9_-]{32,128}$"#, options: .regularExpression) != nil,
                  let record = document?.actions[token],
                  !record.consumed,
                  record.ownerProfileId == snapshot.ownerProfileId,
                  record.profileAuthorizationRevision == snapshot.profileAuthorizationRevision,
                  record.expiresAtMs >= Int64(Date().timeIntervalSince1970 * 1000) else { return nil }
            components.queryItems = [URLQueryItem(name: "token", value: token)]
            return components.url
        }
        components.queryItems = [
            URLQueryItem(name: "imdbId", value: item.imdbId),
            URLQueryItem(name: "type", value: item.type),
            URLQueryItem(name: "title", value: item.title),
            URLQueryItem(name: "posterURL", value: item.posterURL),
            URLQueryItem(name: "year", value: item.year),
        ].filter { $0.value != nil }
        return components.url
    }

    private func releaseDate(for raw: String) -> Date? {
        guard let year = Int(raw.prefix(4)), (1888...2200).contains(year) else {
            return nil
        }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = 1
        components.day = 1
        return components.date
    }
}
