import Foundation
import Observation

struct DiscoveryShelf: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let items: [MediaItem]
}

enum TraktListKind: String, CaseIterable, Sendable {
    case trending
    case anticipated
    case popular

    var title: String {
        switch self {
        case .trending: "Trending"
        case .anticipated: "Most Anticipated"
        case .popular: "Popular on Trakt"
        }
    }
}

@MainActor
@Observable
final class DiscoveryService {
    static let traktClientIDKey = "discovery.trakt.clientID"
    static let tmdbTokenKey = "discovery.tmdb.readAccessToken"

    private let api: APIClient
    private let secrets: SecretStore
    private(set) var isTraktConfigured = false
    private(set) var isTMDBConfigured = false

    init(api: APIClient, secrets: SecretStore) {
        self.api = api
        self.secrets = secrets
        isTraktConfigured = (try? secrets.get(Self.traktClientIDKey))?.isEmpty == false
        isTMDBConfigured = (try? secrets.get(Self.tmdbTokenKey))?.isEmpty == false
    }

    func homeShelves() async -> [DiscoveryShelf] {
        async let trendingMovies = trakt(kind: .trending, media: .movie)
        async let trendingShows = trakt(kind: .trending, media: .series)
        async let anticipatedMovies = trakt(kind: .anticipated, media: .movie)
        async let anticipatedShows = trakt(kind: .anticipated, media: .series)
        async let newMovies = tmdb(path: "movie/now_playing", media: .movie)
        async let newShows = tmdb(path: "tv/on_the_air", media: .series)

        let results = await (
            trendingMovies, trendingShows, anticipatedMovies,
            anticipatedShows, newMovies, newShows
        )
        var shelves = [
            DiscoveryShelf(id: "trakt-trending-movies", title: "Trending Movies", subtitle: "What Trakt viewers are watching now", items: results.0),
            DiscoveryShelf(id: "trakt-trending-series", title: "Trending Series", subtitle: "Shows gaining momentum now", items: results.1),
            DiscoveryShelf(id: "trakt-anticipated-movies", title: "Most Anticipated Movies", subtitle: "Upcoming films with the most interest", items: results.2),
            DiscoveryShelf(id: "trakt-anticipated-series", title: "Most Anticipated Series", subtitle: "Upcoming shows with the most interest", items: results.3)
        ]
        if isTMDBConfigured {
            shelves.insert(DiscoveryShelf(id: "tmdb-new-movies", title: "New Movies", subtitle: "Now playing, from TMDB", items: results.4), at: 2)
            shelves.insert(DiscoveryShelf(id: "tmdb-new-series", title: "New & Airing Series", subtitle: "Airing this week, from TMDB", items: results.5), at: 3)
        }
        return shelves.filter { !$0.items.isEmpty }
    }

    func trakt(kind: TraktListKind, media: DiscoveryMediaType) async -> [MediaItem] {
        guard let clientID = try? secrets.get(Self.traktClientIDKey), !clientID.isEmpty else { return [] }
        let segment = media == .movie ? "movies" : "shows"
        let url = URL(string: "https://api.trakt.tv/\(segment)/\(kind.rawValue)")!
            .appendingQueryItems([URLQueryItem(name: "extended", value: "full"), URLQueryItem(name: "limit", value: "30")])
        let request = APIRequest(
            url: url,
            headers: [
                "Content-Type": "application/json",
                "trakt-api-version": "2",
                "trakt-api-key": clientID
            ],
            blockPrivateNetworks: true
        )
        guard let entries = try? await api.decode([TraktListEntry].self, request: request) else { return [] }
        return entries.compactMap { $0.mediaItem(media: media, source: "Trakt · \(kind.title)") }
    }

    func configureTrakt(clientID rawClientID: String) async throws {
        let clientID = rawClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw DiscoveryError.missingTraktClientID }
        let request = APIRequest(
            url: URL(string: "https://api.trakt.tv/movies/trending?limit=1")!,
            headers: [
                "Content-Type": "application/json",
                "trakt-api-version": "2",
                "trakt-api-key": clientID
            ],
            credentialBearing: true,
            blockPrivateNetworks: true
        )
        _ = try await api.data(request)
        try secrets.set(clientID, for: Self.traktClientIDKey)
        isTraktConfigured = true
    }

    func disconnectTrakt() throws {
        try secrets.remove(Self.traktClientIDKey)
        isTraktConfigured = false
    }

    func configureTMDB(readAccessToken rawToken: String) async throws {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw DiscoveryError.missingToken }
        let request = APIRequest(
            url: URL(string: "https://api.themoviedb.org/3/configuration")!,
            headers: ["Authorization": "Bearer \(token)", "Accept": "application/json"],
            credentialBearing: true,
            blockPrivateNetworks: true
        )
        _ = try await api.data(request)
        try secrets.set(token, for: Self.tmdbTokenKey)
        isTMDBConfigured = true
    }

    func disconnectTMDB() throws {
        try secrets.remove(Self.tmdbTokenKey)
        isTMDBConfigured = false
    }

    private func tmdb(path: String, media: DiscoveryMediaType) async -> [MediaItem] {
        guard let token = try? secrets.get(Self.tmdbTokenKey), !token.isEmpty else { return [] }
        let url = URL(string: "https://api.themoviedb.org/3/\(path)")!
            .appendingQueryItems([URLQueryItem(name: "language", value: "en-US"), URLQueryItem(name: "page", value: "1")])
        let request = APIRequest(
            url: url,
            headers: ["Authorization": "Bearer \(token)", "Accept": "application/json"],
            credentialBearing: true,
            blockPrivateNetworks: true
        )
        guard let page = try? await api.decode(TMDBPage.self, request: request) else { return [] }
        return await withTaskGroup(of: MediaItem.self) { group in
            for result in page.results.prefix(18) {
                group.addTask { [api] in
                    let segment = media == .movie ? "movie" : "tv"
                    let externalURL = URL(string: "https://api.themoviedb.org/3/\(segment)/\(result.id)/external_ids")!
                    let externalRequest = APIRequest(
                        url: externalURL,
                        headers: ["Authorization": "Bearer \(token)", "Accept": "application/json"],
                        credentialBearing: true,
                        blockPrivateNetworks: true
                    )
                    let imdb = try? await api.decode(TMDBExternalIDs.self, request: externalRequest).imdbID
                    return result.mediaItem(media: media, imdbID: imdb ?? nil)
                }
            }
            var items: [MediaItem] = []
            for await item in group { items.append(item) }
            return items.sorted { ($0.year ?? 0, $0.title) > ($1.year ?? 0, $1.title) }
        }
    }
}

enum DiscoveryError: LocalizedError {
    case missingToken
    case missingTraktClientID

    var errorDescription: String? {
        switch self {
        case .missingToken: "Enter a TMDB API Read Access Token"
        case .missingTraktClientID: "Enter a Trakt API client ID"
        }
    }
}

enum DiscoveryMediaType: Sendable { case movie, series }

struct TraktIDs: Decodable, Sendable {
    let imdb: String?
    let tmdb: Int?
}

struct TraktMedia: Decodable, Sendable {
    let title: String
    let year: Int?
    let overview: String?
    let genres: [String]?
    let ids: TraktIDs
}

struct TraktListEntry: Decodable, Sendable {
    let movie: TraktMedia?
    let show: TraktMedia?
    let title: String?
    let year: Int?
    let overview: String?
    let genres: [String]?
    let ids: TraktIDs?

    func mediaItem(media: DiscoveryMediaType, source: String) -> MediaItem? {
        let nested = media == .movie ? movie : show
        let resolvedTitle = nested?.title ?? title
        let resolvedIDs = nested?.ids ?? ids
        guard let resolvedTitle, let resolvedIDs else { return nil }
        let externalID = resolvedIDs.imdb ?? resolvedIDs.tmdb.map { "tmdb:\($0)" }
        guard let externalID else { return nil }
        let type = media == .movie ? "movie" : "series"
        let imdb = resolvedIDs.imdb
        return MediaItem(
            id: "trakt:\(type):\(externalID)",
            title: resolvedTitle,
            overview: nested?.overview ?? overview,
            posterURL: imdb.flatMap { URL(string: "https://images.metahub.space/poster/medium/\($0)/img") },
            backdropURL: imdb.flatMap { URL(string: "https://images.metahub.space/background/medium/\($0)/img") },
            year: nested?.year ?? year,
            genres: nested?.genres ?? genres ?? [],
            provider: source,
            externalID: externalID,
            mediaType: type
        )
    }
}

struct TMDBPage: Decodable, Sendable {
    let results: [TMDBResult]
}

struct TMDBExternalIDs: Decodable, Sendable {
    let imdbID: String?
    enum CodingKeys: String, CodingKey { case imdbID = "imdb_id" }
}

struct TMDBResult: Decodable, Sendable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
    }

    func mediaItem(media: DiscoveryMediaType, imdbID: String? = nil) -> MediaItem {
        let type = media == .movie ? "movie" : "series"
        let date = releaseDate ?? firstAirDate
        return MediaItem(
            id: "tmdb:\(type):\(id)",
            title: title ?? name ?? "Unknown",
            overview: overview,
            posterURL: posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") },
            backdropURL: backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w780\($0)") },
            year: date.flatMap { Int($0.prefix(4)) },
            provider: "TMDB · New Releases",
            externalID: imdbID ?? "tmdb:\(id)",
            mediaType: type
        )
    }
}
