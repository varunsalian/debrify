import Foundation

enum ProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case realDebrid = "Real-Debrid"
    case torBox = "TorBox"
    case premiumize = "Premiumize"
    case allDebrid = "AllDebrid"
    case pikPak = "PikPak"

    var id: String { rawValue }
}

struct MediaItem: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var subtitle: String?
    var overview: String?
    var posterURL: URL?
    var backdropURL: URL?
    var year: Int?
    var genres: [String]
    var provider: String?
    var externalID: String?
    var mediaType: String?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var streamURL: URL?
    var progressSeconds: Double
    var durationSeconds: Double

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        overview: String? = nil,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        year: Int? = nil,
        genres: [String] = [],
        provider: String? = nil,
        externalID: String? = nil,
        mediaType: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        streamURL: URL? = nil,
        progressSeconds: Double = 0,
        durationSeconds: Double = 0
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.overview = overview
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.year = year
        self.genres = genres
        self.provider = provider
        self.externalID = externalID
        self.mediaType = mediaType
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.streamURL = streamURL
        self.progressSeconds = progressSeconds
        self.durationSeconds = durationSeconds
    }

    var progress: Double {
        durationSeconds > 0 ? min(max(progressSeconds / durationSeconds, 0), 1) : 0
    }
}

struct StreamSource: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var url: URL
    var provider: String
    var quality: String?
    var details: String? = nil
    var fileName: String? = nil
    var fileSizeBytes: Int64? = nil
    var videoCodec: String? = nil
    var releaseType: String? = nil
    var container: String? = nil
    var indexer: String? = nil
    var seeders: Int? = nil
    var isCached: Bool? = nil
    var headers: [String: String] = [:]
    var behaviorHints: [String: String] = [:]
}

struct ProviderAccount: Codable, Hashable, Sendable {
    var username: String
    var email: String?
    var plan: String?
    var expiration: Date?
    var points: Double?
}

struct ProviderFile: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var size: Int64?
    var status: String
    var progress: Double?
    var link: URL?
    var createdAt: Date?
    var kind: String
    var remoteID: String? = nil
    var sourceType: String? = nil
    var children: [ProviderChildFile] = []

    var mediaItem: MediaItem {
        MediaItem(id: "provider:\(id)", title: name, subtitle: status, provider: kind, streamURL: link)
    }
}

struct ProviderChildFile: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var size: Int64?
    var mimeType: String?
}

struct AddonManifest: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var description: String?
    var version: String?
    var logo: URL?
    var baseURL: URL
    var catalogs: [AddonCatalog]
}

struct AddonCatalog: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var type: String
    var name: String?
    var extra: [AddonExtra]?
}

struct AddonExtra: Codable, Hashable, Sendable {
    var name: String
    var isRequired: Bool?
    var options: [String]?

    enum CodingKeys: String, CodingKey {
        case name
        case isRequired = "isRequired"
        case options
    }
}

struct WebDAVEntry: Identifiable, Codable, Hashable, Sendable {
    var id: String { href }
    var name: String
    var href: String
    var isDirectory: Bool
    var contentLength: Int64?
    var contentType: String?
}

struct IPTVCategory: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var kind: IPTVKind
}

enum IPTVKind: String, Codable, Hashable, Sendable { case live, vod, series }

struct IPTVChannel: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var iconURL: URL?
    var streamURL: URL
    var categoryID: String?
    var kind: IPTVKind
}

struct IPTVSeries: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var coverURL: URL?
    var plot: String?
    var categoryID: String?
}

struct IPTVEpisode: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var season: Int
    var episode: Int
    var streamURL: URL
    var containerExtension: String
}
