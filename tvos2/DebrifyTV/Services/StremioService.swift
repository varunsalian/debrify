import Foundation
import Observation
import CryptoKit

struct PersistedAddonEnvelope: Codable, Equatable {
    let version: Int
    let addons: [PersistedAddonMetadata]
}

struct PersistedAddonMetadata: Codable, Equatable {
    let id: String
    let name: String
    let description: String?
    let version: String?
    let catalogs: [AddonCatalog]
}

private struct AddonRoutingSecrets: Codable {
    let baseURL: URL
    let logo: URL?
}

final class SecureAddonStore {
    private let persistence: PersistenceStore
    private let secrets: SecretStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(persistence: PersistenceStore, secrets: SecretStore) {
        self.persistence = persistence
        self.secrets = secrets
    }

    func load() -> [AddonManifest] {
        if let envelope = persistence.load(PersistedAddonEnvelope.self, for: .addons), envelope.version == 2 {
            return envelope.addons.compactMap(loadManifest)
        }

        // One-time migration from version 1, which placed tokenized URLs in UserDefaults.
        guard let legacy = persistence.load([AddonManifest].self, for: .addons) else { return [] }
        do {
            try save(legacy)
            return legacy
        } catch {
            // Never leave the known plaintext format behind if Keychain migration fails.
            persistence.remove(.addons)
            return []
        }
    }

    func save(_ addons: [AddonManifest]) throws {
        for addon in addons {
            let routing = AddonRoutingSecrets(baseURL: addon.baseURL, logo: addon.logo)
            let encoded = try encoder.encode(routing).base64EncodedString()
            try secrets.set(encoded, for: routingKey(addon.id))
        }

        let metadata = addons.map {
            PersistedAddonMetadata(id: $0.id, name: $0.name, description: $0.description, version: $0.version, catalogs: $0.catalogs)
        }
        persistence.save(PersistedAddonEnvelope(version: 2, addons: metadata), for: .addons)
    }

    func remove(_ addon: AddonManifest, remaining: [AddonManifest]) throws {
        try secrets.remove(routingKey(addon.id))
        try save(remaining)
    }

    private func loadManifest(_ metadata: PersistedAddonMetadata) -> AddonManifest? {
        guard
            let value = try? secrets.get(routingKey(metadata.id)),
            let data = Data(base64Encoded: value),
            let routing = try? decoder.decode(AddonRoutingSecrets.self, from: data)
        else { return nil }
        return AddonManifest(
            id: metadata.id,
            name: metadata.name,
            description: metadata.description,
            version: metadata.version,
            logo: routing.logo,
            baseURL: routing.baseURL,
            catalogs: metadata.catalogs
        )
    }

    private func routingKey(_ addonID: String) -> String {
        let digest = SHA256.hash(data: Data(addonID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "stremio.addon.routing.\(digest)"
    }
}

@MainActor
@Observable
final class StremioService {
    static let cinemetaManifestURL = URL(string: "https://v3-cinemeta.strem.io/manifest.json")!

    private let api: APIClient
    private let storage: SecureAddonStore
    private let persistence: PersistenceStore
    private(set) var addons: [AddonManifest] = []
    private var webDAVArtworkCache: [String: URL] = [:]
    private var webDAVArtworkMisses = Set<String>()
    private var webDAVArtworkTasks: [String: Task<URL?, Never>] = [:]

    init(api: APIClient, secrets: SecretStore, persistence: PersistenceStore) {
        self.api = api
        self.storage = SecureAddonStore(persistence: persistence, secrets: secrets)
        self.persistence = persistence
        addons = storage.load()
    }

    func ensureCinemeta() async throws {
        if addons.contains(where: Self.isCinemeta) {
            persistence.save(true, for: .cinemetaSeeded)
            return
        }
        guard persistence.load(Bool.self, for: .cinemetaSeeded) != true else { return }
        _ = try await install(manifestURL: Self.cinemetaManifestURL)
        persistence.save(true, for: .cinemetaSeeded)
    }

    func install(manifestURL input: URL) async throws -> AddonManifest {
        let url = normalizedManifestURL(input)
        try URLSafetyPolicy.validate(url, credentialBearing: false, blockPrivateNetworks: true)
        struct RawManifest: Decodable, Sendable {
            var id: String
            var name: String
            var description: String?
            var version: String?
            var logo: String?
            var catalogs: [AddonCatalog]?
        }
        let raw = try await api.decode(RawManifest.self, request: APIRequest(url: url, blockPrivateNetworks: true))
        let manifest = AddonManifest(id: raw.id, name: raw.name, description: raw.description, version: raw.version, logo: raw.logo.flatMap(URL.init(string:)), baseURL: url.deletingLastPathComponent(), catalogs: raw.catalogs ?? [])
        var updated = addons.filter { $0.id != manifest.id }
        updated.append(manifest)
        try storage.save(updated)
        addons = updated
        return manifest
    }

    func remove(_ addon: AddonManifest) throws {
        let updated = addons.filter { $0.id != addon.id }
        try storage.remove(addon, remaining: updated)
        addons = updated
    }

    func catalog(_ catalog: AddonCatalog, addon: AddonManifest, query: String? = nil, skip: Int = 0) async throws -> [MediaItem] {
        let url = Self.catalogURL(baseURL: addon.baseURL, catalog: catalog, query: query, skip: skip)
        struct Response: Decodable, Sendable {
            struct Meta: Decodable, Sendable {
                var id: String
                var name: String
                var description: String?
                var poster: String?
                var background: String?
                var releaseInfo: String?
                var genres: [String]?
            }
            var metas: [Meta]
        }
        let response = try await api.decode(Response.self, request: APIRequest(url: url, blockPrivateNetworks: true))
        return response.metas.map { meta in
            MediaItem(id: "stremio:\(addon.id):\(catalog.type):\(meta.id)", title: meta.name, overview: meta.description, posterURL: meta.poster.flatMap(URL.init(string:)), backdropURL: meta.background.flatMap(URL.init(string:)), year: meta.releaseInfo.flatMap { Int($0.prefix(4)) }, genres: meta.genres ?? [], provider: addon.name, externalID: meta.id, mediaType: catalog.type)
        }
    }

    func trailerURL(for item: MediaItem) async -> URL? {
        guard let externalID = item.externalID else { return nil }
        struct MetaResponse: Decodable, Sendable {
            struct Meta: Decodable, Sendable {
                struct Trailer: Decodable, Sendable { var source: String? }
                var trailers: [Trailer]?
            }
            var meta: Meta
        }
        for addon in addons where addon.catalogs.contains(where: { $0.type == item.mediaType }) {
            let url = Self.metaURL(baseURL: addon.baseURL, type: item.mediaType ?? "movie", id: externalID)
            guard let response = try? await api.decode(MetaResponse.self, request: APIRequest(url: url, blockPrivateNetworks: true)),
                  let source = response.meta.trailers?.compactMap(\.source).first,
                  let trailer = URL(string: "https://www.youtube.com/watch?v=\(source)") else { continue }
            return trailer
        }
        return nil
    }

    func streams(for item: MediaItem) async -> [StreamSource] {
        guard let externalID = item.externalID else { return [] }
        return await withTaskGroup(of: [StreamSource].self) { group in
            for addon in addons {
                group.addTask { [api] in
                    struct Response: Decodable, Sendable {
                        struct Stream: Decodable, Sendable {
                            struct BehaviorHints: Decodable, Sendable {
                                var filename: String?
                                var videoSize: Int64?
                                var bingeGroup: String?
                            }
                            var name: String?
                            var title: String?
                            var description: String?
                            var url: String?
                            var behaviorHints: BehaviorHints?
                        }
                        var streams: [Stream]
                    }
                    let type = item.mediaType == "seriesEpisode" ? "series" : (item.mediaType ?? "movie")
                    let url = Self.streamURL(baseURL: addon.baseURL, type: type, id: externalID)
                    guard let response = try? await api.decode(Response.self, request: APIRequest(url: url, blockPrivateNetworks: true)) else { return [] }
                    return response.streams.compactMap { stream in
                        guard let raw = stream.url, let url = URL(string: raw), (try? URLSafetyPolicy.validate(url, blockPrivateNetworks: true)) != nil else { return nil }
                        let metadata = [stream.description, stream.title]
                            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .reduce(into: [String]()) { values, value in
                                if !values.contains(value) { values.append(value) }
                            }
                            .joined(separator: "\n")
                        let parsed = TorrentStreamMetadata.parse(
                            name: stream.name,
                            details: metadata,
                            fileName: stream.behaviorHints?.filename,
                            videoSize: stream.behaviorHints?.videoSize,
                            bingeGroup: stream.behaviorHints?.bingeGroup
                        )
                        return StreamSource(
                            id: "\(addon.id):\(raw.hashValue)",
                            name: stream.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? addon.name,
                            url: url,
                            provider: addon.name,
                            quality: parsed.resolution,
                            details: metadata.nonEmpty,
                            fileName: stream.behaviorHints?.filename,
                            fileSizeBytes: parsed.fileSizeBytes,
                            videoCodec: parsed.videoCodec,
                            releaseType: parsed.releaseType,
                            container: parsed.container,
                            indexer: parsed.indexer,
                            seeders: parsed.seeders,
                            isCached: parsed.isCached
                        )
                    }
                }
            }
            var result: [StreamSource] = []
            for await streams in group { result.append(contentsOf: streams) }
            return result
        }
    }

    func episodes(for item: MediaItem) async throws -> [MediaItem] {
        guard let externalID = item.externalID else { return [] }
        try await ensureCinemeta()
        guard let cinemeta = addons.first(where: Self.isCinemeta) else { return [] }

        struct Response: Decodable, Sendable {
            struct Meta: Decodable, Sendable {
                struct Video: Decodable, Sendable {
                    var id: String
                    var title: String?
                    var season: Int?
                    var episode: Int?
                    var overview: String?
                    var thumbnail: String?
                }
                var videos: [Video]?
            }
            var meta: Meta
        }

        let url = Self.metaURL(baseURL: cinemeta.baseURL, type: "series", id: externalID)
        let response = try await api.decode(Response.self, request: APIRequest(url: url, blockPrivateNetworks: true))
        return (response.meta.videos ?? []).map { video in
            let season = video.season ?? 0
            let episode = video.episode ?? 0
            return MediaItem(
                id: "stremio:episode:\(video.id)",
                title: video.title ?? "Episode \(episode)",
                subtitle: "Season \(season) • Episode \(episode)",
                overview: video.overview,
                posterURL: video.thumbnail.flatMap(URL.init(string:)) ?? item.posterURL,
                backdropURL: item.backdropURL,
                year: item.year,
                genres: item.genres,
                provider: item.provider,
                externalID: video.id,
                mediaType: "seriesEpisode",
                seasonNumber: season,
                episodeNumber: episode
            )
        }
        .sorted {
            ($0.seasonNumber ?? 0, $0.episodeNumber ?? 0) < ($1.seasonNumber ?? 0, $1.episodeNumber ?? 0)
        }
    }

    func search(_ query: String) async -> [MediaItem] {
        try? await ensureCinemeta()
        let combined = await withTaskGroup(of: [MediaItem].self) { group in
            for addon in addons {
                for catalog in addon.catalogs where catalog.extra?.contains(where: { $0.name == "search" }) == true {
                    group.addTask { [weak self] in (try? await self?.catalog(catalog, addon: addon, query: query)) ?? [] }
                }
            }
            var result: [MediaItem] = []
            for await items in group { result.append(contentsOf: items) }
            return result
        }
        var seen = Set<String>()
        return combined.filter { item in
            let identity = "\(item.mediaType ?? "other"):\(item.externalID ?? item.id)"
            return seen.insert(identity).inserted
        }
    }

    func artworkURL(forWebDAVName name: String) async -> URL? {
        let hint = WebDAVMediaHint.parse(name)
        guard hint.query.count >= 2 else { return nil }
        let key = "\(hint.preferredType ?? "any"):\(hint.query.lowercased())"
        if let cached = webDAVArtworkCache[key] { return cached }
        if webDAVArtworkMisses.contains(key) { return nil }
        if let task = webDAVArtworkTasks[key] { return await task.value }

        let task = Task { [weak self] () -> URL? in
            guard let self else { return nil }
            let results = await self.search(hint.query)
            let normalizedQuery = WebDAVMediaHint.normalized(hint.query)
            let exact = results.first {
                WebDAVMediaHint.normalized($0.title) == normalizedQuery &&
                (hint.preferredType == nil || $0.mediaType == hint.preferredType)
            }
            return (exact ?? results.first { hint.preferredType == nil || $0.mediaType == hint.preferredType })?.posterURL
        }
        webDAVArtworkTasks[key] = task
        let url = await task.value
        webDAVArtworkTasks[key] = nil
        if let url { webDAVArtworkCache[key] = url } else { webDAVArtworkMisses.insert(key) }
        return url
    }

    nonisolated static func catalogURL(baseURL: URL, catalog: AddonCatalog, query: String?, skip: Int = 0) -> URL {
        var url = baseURL
            .appending(path: "catalog")
            .appending(path: catalog.type)
            .appending(path: catalog.id)
        let cleanQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        var extras: [String] = []
        if let cleanQuery, !cleanQuery.isEmpty { extras.append("search=\(cleanQuery)") }
        if skip > 0 { extras.append("skip=\(skip)") }
        if extras.isEmpty {
            url = url.appendingPathExtension("json")
        } else {
            url = url.appending(path: extras.joined(separator: "&") + ".json")
        }
        return url
    }

    nonisolated static func metaURL(baseURL: URL, type: String, id: String) -> URL {
        baseURL.appending(path: "meta/\(type)/\(id).json")
    }

    nonisolated static func streamURL(baseURL: URL, type: String, id: String) -> URL {
        baseURL.appending(path: "stream/\(type)/\(id).json")
    }

    private nonisolated static func isCinemeta(_ addon: AddonManifest) -> Bool {
        addon.id.lowercased().contains("cinemeta") || addon.baseURL.host?.lowercased() == "v3-cinemeta.strem.io"
    }

    private func normalizedManifestURL(_ url: URL) -> URL {
        if url.lastPathComponent == "manifest.json" { return url }
        return url.appending(path: "manifest.json")
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

struct TorrentStreamMetadata: Equatable {
    var resolution: String?
    var fileSizeBytes: Int64?
    var videoCodec: String?
    var releaseType: String?
    var container: String?
    var indexer: String?
    var seeders: Int?
    var isCached: Bool?

    static func parse(name: String?, details: String?, fileName: String?, videoSize: Int64?, bingeGroup: String?) -> Self {
        let combined = [name, details, fileName, bingeGroup].compactMap { $0 }.joined(separator: "\n")
        let resolution = match(#"(?i)\b(8K|4K|2160p|1440p|1080p|720p|576p|480p)\b"#, in: combined, group: 1)
        let codec = match(#"(?i)\b(AV1|HEVC|H[ ._-]?265|X265|H[ ._-]?264|X264|XVID)\b"#, in: combined, group: 1)
        let release = match(#"(?i)\b(REMUX|BluRay|BRRip|WEB[ ._-]?DL|WEBRip|HDTV|DVDRip)\b"#, in: combined, group: 1)
        let container = match(#"(?i)\.(mkv|mp4|m4v|avi|mov|ts)\b"#, in: combined, group: 1)?.uppercased()
        let indexer = match(#"⚙️\s*([^\n\r]+)"#, in: combined, group: 1)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let seeders = match(#"👤\s*(\d+)"#, in: combined, group: 1).flatMap(Int.init)
        let cached = match(#"\[(?:RD|TB|PM|AD|DL)\+\]"#, in: combined) != nil ? true : nil
        return Self(
            resolution: resolution?.uppercased() == "2160P" ? "4K" : resolution,
            fileSizeBytes: videoSize.flatMap { $0 > 0 ? $0 : nil } ?? parsedSize(in: combined),
            videoCodec: codec,
            releaseType: release,
            container: container,
            indexer: indexer,
            seeders: seeders,
            isCached: cached
        )
    }

    private static func parsedSize(in value: String) -> Int64? {
        guard
            let amountText = match(#"(?i)(?:💾\s*)?(\d+(?:[.,]\d+)?)\s*(TB|GB|MB|KB|TiB|GiB|MiB)\b"#, in: value, group: 1),
            let unit = match(#"(?i)(?:💾\s*)?\d+(?:[.,]\d+)?\s*(TB|GB|MB|KB|TiB|GiB|MiB)\b"#, in: value, group: 1),
            let amount = Double(amountText.replacingOccurrences(of: ",", with: "."))
        else { return nil }
        let multiplier: Double
        switch unit.lowercased() {
        case "tb", "tib": multiplier = 1_099_511_627_776
        case "gb", "gib": multiplier = 1_073_741_824
        case "mb", "mib": multiplier = 1_048_576
        default: multiplier = 1_024
        }
        return Int64(amount * multiplier)
    }

    private static func match(_ pattern: String, in value: String, group: Int = 0) -> String? {
        guard
            let expression = try? NSRegularExpression(pattern: pattern),
            let result = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
            group < result.numberOfRanges,
            let range = Range(result.range(at: group), in: value)
        else { return nil }
        return String(value[range])
    }
}

struct WebDAVMediaHint: Equatable {
    var query: String
    var preferredType: String?

    static func parse(_ fileName: String) -> Self {
        var value = fileName.removingPercentEncoding ?? fileName
        if let queryRange = value.range(of: #"(?i)\bS\d{1,2}E\d{1,3}\b"#, options: .regularExpression) {
            value = String(value[..<queryRange.lowerBound])
            return Self(query: cleaned(value), preferredType: "series")
        }
        if let yearRange = value.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression) {
            value = String(value[..<yearRange.lowerBound])
        } else if let extensionRange = value.range(of: #"(?i)\.(?:mkv|mp4|m4v|avi|mov|ts)$"#, options: .regularExpression) {
            value.removeSubrange(extensionRange)
        }
        return Self(query: cleaned(value), preferredType: nil)
    }

    static func normalized(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    private static func cleaned(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[._]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-")))
    }
}
