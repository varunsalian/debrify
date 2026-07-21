import Foundation
import Observation

struct XtreamConfiguration: Codable, Hashable {
    var baseURL: URL
    var username: String
}

@MainActor
@Observable
final class XtreamService {
    private let api: APIClient
    private let secrets: SecretStore
    private let persistence: PersistenceStore
    private(set) var configuration: XtreamConfiguration?

    init(api: APIClient, secrets: SecretStore, persistence: PersistenceStore) {
        self.api = api
        self.secrets = secrets
        self.persistence = persistence
        configuration = persistence.load(XtreamConfiguration.self, for: .xtreamConfiguration)
    }

    func configure(url: URL, username: String, password: String) async throws {
        try URLSafetyPolicy.validate(url, credentialBearing: true)
        try secrets.set(password, for: "xtream.password")
        let value = XtreamConfiguration(baseURL: url, username: username)
        configuration = value
        persistence.save(value, for: .xtreamConfiguration)
        _ = try await categories(kind: .live)
    }

    func disconnect() throws {
        try secrets.remove("xtream.password")
        configuration = nil
        persistence.remove(.xtreamConfiguration)
    }

    func categories(kind: IPTVKind) async throws -> [IPTVCategory] {
        let action: String = switch kind {
        case .live: "get_live_categories"
        case .vod: "get_vod_categories"
        case .series: "get_series_categories"
        }
        let data = try await request(action: action)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ProviderError.malformedResponse }
        return rows.map { IPTVCategory(id: String(describing: $0["category_id"] ?? ""), name: $0["category_name"] as? String ?? "Category", kind: kind) }
    }

    func channels(category: IPTVCategory) async throws -> [IPTVChannel] {
        guard let config = configuration, let password = try secrets.get("xtream.password") else { throw ProviderError.missingCredential }
        let action: String = switch category.kind {
        case .live: "get_live_streams"
        case .vod: "get_vod_streams"
        case .series: "get_series"
        }
        let data = try await request(action: action, extra: [URLQueryItem(name: "category_id", value: category.id)])
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ProviderError.malformedResponse }
        return rows.compactMap { row in
            let streamID = String(describing: row["stream_id"] ?? row["series_id"] ?? "")
            guard !streamID.isEmpty else { return nil }
            let extensionName = row["container_extension"] as? String ?? "m3u8"
            let component = category.kind == .live ? "live" : "movie"
            guard category.kind != .series, let url = URL(string: "\(config.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(component)/\(config.username)/\(password)/\(streamID).\(extensionName)") else { return nil }
            return IPTVChannel(id: "\(category.kind.rawValue):\(streamID)", name: row["name"] as? String ?? "Channel", iconURL: URL(string: row["stream_icon"] as? String ?? row["cover"] as? String ?? ""), streamURL: url, categoryID: category.id, kind: category.kind)
        }
    }

    func series(category: IPTVCategory) async throws -> [IPTVSeries] {
        let data = try await request(action: "get_series", extra: [URLQueryItem(name: "category_id", value: category.id)])
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ProviderError.malformedResponse }
        return rows.compactMap { row in
            let id = String(describing: row["series_id"] ?? "")
            guard !id.isEmpty else { return nil }
            return IPTVSeries(id: id, name: row["name"] as? String ?? "Series", coverURL: URL(string: row["cover"] as? String ?? ""), plot: row["plot"] as? String, categoryID: category.id)
        }
    }

    func episodes(series: IPTVSeries) async throws -> [IPTVEpisode] {
        guard let config = configuration, let password = try secrets.get("xtream.password") else { throw ProviderError.missingCredential }
        let data = try await request(action: "get_series_info", extra: [URLQueryItem(name: "series_id", value: series.id)])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let seasons = root["episodes"] as? [String: [[String: Any]]] else { throw ProviderError.malformedResponse }
        var result: [IPTVEpisode] = []
        for (seasonKey, rows) in seasons {
            for row in rows {
                let id = String(describing: row["id"] ?? "")
                guard !id.isEmpty else { continue }
                let extensionName = row["container_extension"] as? String ?? "mp4"
                let base = config.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard let url = URL(string: "\(base)/series/\(config.username)/\(password)/\(id).\(extensionName)") else { continue }
                let info = row["info"] as? [String: Any]
                result.append(IPTVEpisode(id: id, title: row["title"] as? String ?? info?["name"] as? String ?? "Episode", season: Int(seasonKey) ?? 0, episode: (row["episode_num"] as? NSNumber)?.intValue ?? 0, streamURL: url, containerExtension: extensionName))
            }
        }
        return result.sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
    }

    func search(_ query: String) async -> [MediaItem] {
        var result: [MediaItem] = []
        for kind in [IPTVKind.live, .vod] {
            guard let categories = try? await categories(kind: kind) else { continue }
            for category in categories {
                guard let channels = try? await channels(category: category) else { continue }
                result += channels.filter { $0.name.localizedCaseInsensitiveContains(query) }.map {
                    MediaItem(id: "iptv:\($0.id)", title: $0.name, posterURL: $0.iconURL, provider: "IPTV", streamURL: $0.streamURL)
                }
            }
        }
        return result
    }

    private func request(action: String, extra: [URLQueryItem] = []) async throws -> Data {
        guard let config = configuration, let password = try secrets.get("xtream.password") else { throw ProviderError.missingCredential }
        var url = config.baseURL.appending(path: "player_api.php").appendingQueryItems([
            URLQueryItem(name: "username", value: config.username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "action", value: action)
        ] + extra)
        if url.path.contains("//player_api") { url = URL(string: url.absoluteString.replacingOccurrences(of: "//player_api", with: "/player_api")) ?? url }
        return try await api.data(APIRequest(url: url, credentialBearing: true))
    }
}
