import Foundation
import Observation

protocol ProviderService: Sendable {
    var kind: ProviderKind { get }
    func account(token: String) async throws -> ProviderAccount
    func files(token: String) async throws -> [ProviderFile]
    func resolve(_ url: URL, token: String) async throws -> StreamSource
    func resolve(_ file: ProviderFile, child: ProviderChildFile?, token: String) async throws -> StreamSource
    func addMagnet(_ magnet: String, token: String) async throws
}

extension ProviderService {
    func resolve(_ file: ProviderFile, child: ProviderChildFile?, token: String) async throws -> StreamSource {
        guard let link = file.link else { throw ProviderError.unsupported("This provider item does not have a playable file yet") }
        return try await resolve(link, token: token)
    }
}

enum ProviderError: LocalizedError {
    case missingCredential
    case malformedResponse
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .missingCredential: "Connect this provider in Settings first"
        case .malformedResponse: "The provider returned an unexpected response"
        case .unsupported(let message): message
        }
    }
}

@MainActor
@Observable
final class ProviderRegistry {
    private let secrets: SecretStore
    private let services: [ProviderKind: any ProviderService]
    private(set) var connected: Set<ProviderKind> = []

    init(api: APIClient, secrets: SecretStore) {
        self.secrets = secrets
        self.services = [
            .realDebrid: RealDebridService(api: api),
            .torBox: TorBoxService(api: api),
            .premiumize: PremiumizeService(api: api),
            .allDebrid: AllDebridService(api: api),
            .pikPak: PikPakService(api: api)
        ]
        refreshConnections()
    }

    func refreshConnections() {
        connected = Set(ProviderKind.allCases.filter { (try? secrets.get(secretKey($0))) != nil })
    }

    func connect(_ kind: ProviderKind, token: String) async throws -> ProviderAccount {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let service = services[kind] else { throw ProviderError.missingCredential }
        let account = try await service.account(token: clean)
        try secrets.set(clean, for: secretKey(kind))
        connected.insert(kind)
        return account
    }

    func disconnect(_ kind: ProviderKind) throws {
        try secrets.remove(secretKey(kind))
        connected.remove(kind)
    }

    func account(_ kind: ProviderKind) async throws -> ProviderAccount {
        let (service, token) = try credentials(for: kind)
        return try await service.account(token: token)
    }

    func files(_ kind: ProviderKind) async throws -> [ProviderFile] {
        let (service, token) = try credentials(for: kind)
        return try await service.files(token: token)
    }

    func resolve(_ url: URL, using kind: ProviderKind) async throws -> StreamSource {
        let (service, token) = try credentials(for: kind)
        return try await service.resolve(url, token: token)
    }

    func resolve(_ file: ProviderFile, child: ProviderChildFile?, using kind: ProviderKind) async throws -> StreamSource {
        let (service, token) = try credentials(for: kind)
        return try await service.resolve(file, child: child, token: token)
    }

    func addMagnet(_ magnet: String, using kind: ProviderKind) async throws {
        let (service, token) = try credentials(for: kind)
        try await service.addMagnet(magnet, token: token)
    }

    func search(_ query: String) async -> [MediaItem] {
        await withTaskGroup(of: [MediaItem].self) { group in
            for kind in connected {
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    let files = (try? await self.files(kind)) ?? []
                    return files.filter { $0.name.localizedCaseInsensitiveContains(query) }.map(\.mediaItem)
                }
            }
            var result: [MediaItem] = []
            for await items in group { result.append(contentsOf: items) }
            return result
        }
    }

    private func credentials(for kind: ProviderKind) throws -> (any ProviderService, String) {
        guard let service = services[kind], let token = try secrets.get(secretKey(kind)), !token.isEmpty else {
            throw ProviderError.missingCredential
        }
        return (service, token)
    }

    private func secretKey(_ kind: ProviderKind) -> String { "provider.\(kind.rawValue).token" }
}

private protocol JSONProviderService: ProviderService {}

private extension JSONProviderService {
    func dictionary(from data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.malformedResponse
        }
        return value
    }

    func array(from data: Data, nested key: String? = nil) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data)
        if let array = object as? [[String: Any]] { return array }
        if let key, let dictionary = object as? [String: Any], let array = dictionary[key] as? [[String: Any]] { return array }
        throw ProviderError.malformedResponse
    }

    func date(_ raw: Any?) -> Date? {
        if let seconds = raw as? TimeInterval { return Date(timeIntervalSince1970: seconds) }
        guard let string = raw as? String else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }

    func form(_ values: [String: String]) -> Data {
        values.map { key, value in
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
            return "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}

final class RealDebridService: JSONProviderService, @unchecked Sendable {
    let kind = ProviderKind.realDebrid
    private let api: APIClient
    private let base = URL(string: "https://api.real-debrid.com/rest/1.0")!
    init(api: APIClient) { self.api = api }

    func account(token: String) async throws -> ProviderAccount {
        let value = try dictionary(from: await request("user", token: token))
        return ProviderAccount(
            username: value["username"] as? String ?? "Real-Debrid",
            email: value["email"] as? String,
            plan: value["type"] as? String,
            expiration: date(value["expiration"]),
            points: value["points"] as? Double
        )
    }

    func files(token: String) async throws -> [ProviderFile] {
        let downloads = try array(from: await request("downloads", token: token))
        let torrents = try array(from: await request("torrents", token: token))
        let mappedDownloads = downloads.map {
            ProviderFile(id: "rd-download-\($0["id"] ?? UUID().uuidString)", name: $0["filename"] as? String ?? "Download", size: ($0["filesize"] as? NSNumber)?.int64Value, status: "Ready", link: URL(string: $0["download"] as? String ?? ""), createdAt: date($0["generated"]), kind: kind.rawValue)
        }
        let mappedTorrents = torrents.map {
            let firstLink = ($0["links"] as? [String])?.first ?? ""
            return ProviderFile(id: "rd-torrent-\($0["id"] ?? UUID().uuidString)", name: $0["filename"] as? String ?? "Torrent", size: ($0["bytes"] as? NSNumber)?.int64Value, status: $0["status"] as? String ?? "Unknown", progress: ($0["progress"] as? NSNumber).map { $0.doubleValue / 100 }, link: URL(string: firstLink), createdAt: date($0["added"]), kind: kind.rawValue)
        }
        return mappedDownloads + mappedTorrents
    }

    func resolve(_ url: URL, token: String) async throws -> StreamSource {
        let data = try await api.data(APIRequest(url: base.appending(path: "unrestrict/link"), method: "POST", headers: auth(token).merging(["Content-Type": "application/x-www-form-urlencoded"]) { $1 }, body: form(["link": url.absoluteString]), credentialBearing: true))
        let value = try dictionary(from: data)
        guard let link = URL(string: value["download"] as? String ?? "") else { throw ProviderError.malformedResponse }
        return StreamSource(id: UUID().uuidString, name: value["filename"] as? String ?? "Real-Debrid", url: link, provider: kind.rawValue, quality: value["mimeType"] as? String)
    }

    func addMagnet(_ magnet: String, token: String) async throws {
        _ = try await api.data(APIRequest(url: base.appending(path: "torrents/addMagnet"), method: "POST", headers: auth(token).merging(["Content-Type": "application/x-www-form-urlencoded"]) { $1 }, body: form(["magnet": magnet]), credentialBearing: true))
    }

    private func request(_ path: String, token: String) async throws -> Data {
        try await api.data(APIRequest(url: base.appending(path: path), headers: auth(token), credentialBearing: true))
    }
    private func auth(_ token: String) -> [String: String] { ["Authorization": "Bearer \(token)"] }
}

final class TorBoxService: JSONProviderService, @unchecked Sendable {
    let kind = ProviderKind.torBox
    private let api: APIClient
    private let base = URL(string: "https://api.torbox.app/v1/api")!
    init(api: APIClient) { self.api = api }

    func account(token: String) async throws -> ProviderAccount {
        let root = try dictionary(from: await get("user/me", token: token))
        let value = root["data"] as? [String: Any] ?? root
        return ProviderAccount(username: value["email"] as? String ?? "TorBox", email: value["email"] as? String, plan: String(describing: value["plan"] ?? ""), expiration: date(value["expiration"]), points: nil)
    }

    func files(token: String) async throws -> [ProviderFile] {
        let endpoints = [("torrents/mylist", "Torrent", "torrent"), ("webdl/mylist", "WebDL", "webdl"), ("usenet/mylist", "Usenet", "usenet")]
        var result: [ProviderFile] = []
        for (endpoint, label, sourceType) in endpoints {
            guard let root = try? dictionary(from: await get(endpoint, token: token)), let rows = root["data"] as? [[String: Any]] else { continue }
            result += rows.map { row in
                let remoteID = String(describing: row["id"] ?? "")
                let children = (row["files"] as? [[String: Any]] ?? []).compactMap { raw -> ProviderChildFile? in
                    let fileID = String(describing: raw["id"] ?? "")
                    guard !fileID.isEmpty else { return nil }
                    let displayName = raw["short_name"] as? String ?? raw["name"] as? String ?? "File"
                    return ProviderChildFile(id: fileID, name: displayName, size: (raw["size"] as? NSNumber)?.int64Value, mimeType: raw["mimetype"] as? String)
                }
                return ProviderFile(id: "tb-\(label)-\(remoteID)", name: row["name"] as? String ?? label, size: (row["size"] as? NSNumber)?.int64Value, status: row["download_state"] as? String ?? row["download_status"] as? String ?? "Unknown", progress: (row["progress"] as? NSNumber)?.doubleValue, link: URL(string: row["download_url"] as? String ?? ""), createdAt: date(row["created_at"]), kind: kind.rawValue, remoteID: remoteID, sourceType: sourceType, children: children)
            }
        }
        return result
    }

    func resolve(_ url: URL, token: String) async throws -> StreamSource {
        return StreamSource(id: UUID().uuidString, name: "TorBox", url: url, provider: kind.rawValue)
    }

    func resolve(_ file: ProviderFile, child: ProviderChildFile?, token: String) async throws -> StreamSource {
        guard let remoteID = file.remoteID, !remoteID.isEmpty else {
            guard let link = file.link else { throw ProviderError.unsupported("TorBox has not exposed this transfer yet") }
            return try await resolve(link, token: token)
        }
        guard let child else { throw ProviderError.unsupported("Choose a file inside this TorBox transfer") }
        let sourceType = file.sourceType ?? "torrent"
        let endpointPath: String
        let identifierName: String
        switch sourceType {
        case "webdl": endpointPath = "webdl/requestdl"; identifierName = "web_id"
        case "usenet": endpointPath = "usenet/requestdl"; identifierName = "usenet_id"
        default: endpointPath = "torrents/requestdl"; identifierName = "torrent_id"
        }
        let endpoint = base.appending(path: endpointPath).appendingQueryItems([
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: identifierName, value: remoteID),
            URLQueryItem(name: "file_id", value: child.id),
            URLQueryItem(name: "zip_link", value: "false"),
            URLQueryItem(name: "redirect", value: "false")
        ])
        let root = try dictionary(from: try await api.data(APIRequest(url: endpoint, headers: ["Authorization": "Bearer \(token)"], credentialBearing: true)))
        let string = root["data"] as? String ?? (root["data"] as? [String: Any])?["url"] as? String
        guard let string, let resolved = URL(string: string) else { throw ProviderError.malformedResponse }
        return StreamSource(id: "torbox:\(sourceType):\(remoteID):\(child.id)", name: child.name, url: resolved, provider: kind.rawValue)
    }

    func addMagnet(_ magnet: String, token: String) async throws {
        _ = try await api.data(APIRequest(url: base.appending(path: "torrents/createtorrent"), method: "POST", headers: ["Authorization": "Bearer \(token)", "Content-Type": "application/x-www-form-urlencoded"], body: form(["magnet": magnet]), credentialBearing: true))
    }

    private func get(_ path: String, token: String) async throws -> Data {
        try await api.data(APIRequest(url: base.appending(path: path), headers: ["Authorization": "Bearer \(token)"], credentialBearing: true))
    }
}

final class PremiumizeService: JSONProviderService, @unchecked Sendable {
    let kind = ProviderKind.premiumize
    private let api: APIClient
    private let base = URL(string: "https://www.premiumize.me/api")!
    init(api: APIClient) { self.api = api }

    func account(token: String) async throws -> ProviderAccount {
        let value = try dictionary(from: await get("account/info", token: token))
        return ProviderAccount(username: value["customer_id"] as? String ?? "Premiumize", email: nil, plan: "Premium", expiration: (value["premium_until"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)), points: (value["space_used"] as? NSNumber)?.doubleValue)
    }

    func files(token: String) async throws -> [ProviderFile] {
        let root = try dictionary(from: await get("folder/list", token: token))
        let rows = root["content"] as? [[String: Any]] ?? []
        return rows.map { row in
            ProviderFile(id: "pm-\(row["id"] ?? UUID().uuidString)", name: row["name"] as? String ?? "Cloud item", size: (row["size"] as? NSNumber)?.int64Value, status: row["type"] as? String ?? "Ready", link: URL(string: row["link"] as? String ?? row["stream_link"] as? String ?? ""), createdAt: date(row["created_at"]), kind: kind.rawValue)
        }
    }

    func resolve(_ url: URL, token: String) async throws -> StreamSource {
        let endpoint = base.appending(path: "transfer/directdl").appendingQueryItems([URLQueryItem(name: "apikey", value: token), URLQueryItem(name: "src", value: url.absoluteString)])
        let value = try dictionary(from: try await api.data(APIRequest(url: endpoint, credentialBearing: true)))
        let location = value["location"] as? String ?? (value["content"] as? [[String: Any]])?.first?["link"] as? String
        guard let location, let resolved = URL(string: location) else { throw ProviderError.malformedResponse }
        return StreamSource(id: UUID().uuidString, name: "Premiumize", url: resolved, provider: kind.rawValue)
    }

    func addMagnet(_ magnet: String, token: String) async throws {
        let endpoint = base.appending(path: "transfer/create").appendingQueryItems([URLQueryItem(name: "apikey", value: token)])
        _ = try await api.data(APIRequest(url: endpoint, method: "POST", headers: ["Content-Type": "application/x-www-form-urlencoded"], body: form(["src": magnet]), credentialBearing: true))
    }

    private func get(_ path: String, token: String) async throws -> Data {
        try await api.data(APIRequest(url: base.appending(path: path).appendingQueryItems([URLQueryItem(name: "apikey", value: token)]), credentialBearing: true))
    }
}

final class AllDebridService: JSONProviderService, @unchecked Sendable {
    let kind = ProviderKind.allDebrid
    private let api: APIClient
    private let base = URL(string: "https://api.alldebrid.com/v4")!
    init(api: APIClient) { self.api = api }

    func account(token: String) async throws -> ProviderAccount {
        let root = try dictionary(from: await get("user", token: token))
        let value = (root["data"] as? [String: Any])?["user"] as? [String: Any] ?? root
        return ProviderAccount(username: value["username"] as? String ?? "AllDebrid", email: value["email"] as? String, plan: value["isPremium"] as? Bool == true ? "Premium" : "Free", expiration: (value["premiumUntil"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)), points: nil)
    }

    func files(token: String) async throws -> [ProviderFile] {
        let root = try dictionary(from: await get("magnet/status", token: token))
        let data = root["data"] as? [String: Any]
        let rows = data?["magnets"] as? [[String: Any]] ?? []
        return rows.map { row in
            ProviderFile(id: "ad-\(row["id"] ?? UUID().uuidString)", name: row["filename"] as? String ?? "Magnet", size: (row["size"] as? NSNumber)?.int64Value, status: row["status"] as? String ?? "Unknown", progress: (row["downloaded"] as? NSNumber).map { $0.doubleValue / 100 }, link: URL(string: (row["links"] as? [[String: Any]])?.first?["link"] as? String ?? ""), createdAt: date(row["uploadDate"]), kind: kind.rawValue)
        }
    }

    func resolve(_ url: URL, token: String) async throws -> StreamSource {
        let endpoint = authorized("link/unlock", token: token).appendingQueryItems([URLQueryItem(name: "link", value: url.absoluteString)])
        let root = try dictionary(from: try await api.data(APIRequest(url: endpoint, credentialBearing: true)))
        let value = root["data"] as? [String: Any] ?? root
        guard let link = URL(string: value["link"] as? String ?? "") else { throw ProviderError.malformedResponse }
        return StreamSource(id: UUID().uuidString, name: value["filename"] as? String ?? "AllDebrid", url: link, provider: kind.rawValue)
    }

    func addMagnet(_ magnet: String, token: String) async throws {
        let endpoint = authorized("magnet/upload", token: token).appendingQueryItems([URLQueryItem(name: "magnets[]", value: magnet)])
        _ = try await api.data(APIRequest(url: endpoint, credentialBearing: true))
    }

    private func get(_ path: String, token: String) async throws -> Data {
        try await api.data(APIRequest(url: authorized(path, token: token), credentialBearing: true))
    }
    private func authorized(_ path: String, token: String) -> URL {
        base.appending(path: path).appendingQueryItems([URLQueryItem(name: "agent", value: "DebrifyTV"), URLQueryItem(name: "apikey", value: token)])
    }
}

final class PikPakService: JSONProviderService, @unchecked Sendable {
    let kind = ProviderKind.pikPak
    private let api: APIClient
    private let base = URL(string: "https://api-drive.mypikpak.com/drive/v1")!
    init(api: APIClient) { self.api = api }

    func account(token: String) async throws -> ProviderAccount {
        let value = try dictionary(from: try await api.data(request("about", token: token)))
        return ProviderAccount(username: value["name"] as? String ?? value["email"] as? String ?? "PikPak", email: value["email"] as? String, plan: value["kind"] as? String, expiration: nil, points: nil)
    }

    func files(token: String) async throws -> [ProviderFile] {
        let endpoint = base.appending(path: "files").appendingQueryItems([URLQueryItem(name: "parent_id", value: ""), URLQueryItem(name: "limit", value: "100")])
        let root = try dictionary(from: try await api.data(APIRequest(url: endpoint, headers: bearer(token), credentialBearing: true)))
        let rows = root["files"] as? [[String: Any]] ?? []
        return rows.map { row in
            let links = row["links"] as? [String: Any]
            return ProviderFile(id: "pp-\(row["id"] ?? UUID().uuidString)", name: row["name"] as? String ?? "PikPak file", size: (row["size"] as? NSNumber)?.int64Value, status: row["trashed"] as? Bool == true ? "Trashed" : "Ready", link: URL(string: links?["application/octet-stream"] as? String ?? row["web_content_link"] as? String ?? ""), createdAt: date(row["created_time"]), kind: kind.rawValue)
        }
    }

    func resolve(_ url: URL, token: String) async throws -> StreamSource {
        if url.scheme == "https" { return StreamSource(id: UUID().uuidString, name: "PikPak", url: url, provider: kind.rawValue) }
        throw ProviderError.unsupported("PikPak requires a cloud file URL")
    }

    func addMagnet(_ magnet: String, token: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["kind": "drive#file", "name": "Debrify transfer", "upload_type": "UPLOAD_TYPE_URL", "url": ["url": magnet]])
        _ = try await api.data(APIRequest(url: base.appending(path: "files"), method: "POST", headers: bearer(token).merging(["Content-Type": "application/json"]) { $1 }, body: body, credentialBearing: true))
    }

    private func request(_ path: String, token: String) -> APIRequest {
        APIRequest(url: base.appending(path: path), headers: bearer(token), credentialBearing: true)
    }
    private func bearer(_ token: String) -> [String: String] { ["Authorization": "Bearer \(token)"] }
}
