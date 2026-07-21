import Foundation

enum NetworkPolicyError: LocalizedError, Equatable {
    case invalidURL
    case insecureTransport
    case localNetworkDestination
    case unsupportedScheme
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid URL"
        case .insecureTransport: "A secure HTTPS connection is required"
        case .localNetworkDestination: "Local and private-network addresses are not allowed"
        case .unsupportedScheme: "Unsupported URL scheme"
        case .badResponse(let code): "Server returned HTTP \(code)"
        }
    }
}

enum URLSafetyPolicy {
    static func validate(_ url: URL, credentialBearing: Bool = false, blockPrivateNetworks: Bool = false) throws {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else {
            throw NetworkPolicyError.invalidURL
        }
        guard scheme == "https" || (!credentialBearing && scheme == "http") else {
            throw scheme == "http" ? NetworkPolicyError.insecureTransport : NetworkPolicyError.unsupportedScheme
        }
        if blockPrivateNetworks, isPrivate(host: host) { throw NetworkPolicyError.localNetworkDestination }
    }

    static func isPrivate(host: String) -> Bool {
        let clean = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if clean == "localhost" || clean == "localhost.local" || clean.hasSuffix(".local") { return true }
        if clean == "::1" || clean.hasPrefix("fe80:") || clean.hasPrefix("fc") || clean.hasPrefix("fd") { return true }
        let parts = clean.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        let a = parts[0], b = parts[1]
        return a == 10 || a == 127 || a == 0 || (a == 169 && b == 254) ||
            (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) || a >= 224
    }
}

struct APIRequest: Sendable {
    var url: URL
    var method: String = "GET"
    var headers: [String: String] = [:]
    var body: Data?
    var credentialBearing = false
    var blockPrivateNetworks = false
}

actor APIClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func data(_ request: APIRequest) async throws -> Data {
        try URLSafetyPolicy.validate(
            request.url,
            credentialBearing: request.credentialBearing,
            blockPrivateNetworks: request.blockPrivateNetworks
        )
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = 30
        request.headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkPolicyError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    func decode<T: Decodable & Sendable>(_ type: T.Type, request: APIRequest) async throws -> T {
        let data = try await data(request)
        return try decoder.decode(type, from: data)
    }

    func json(_ request: APIRequest) async throws -> Any {
        try JSONSerialization.jsonObject(with: try await data(request))
    }
}

extension URL {
    func appendingQueryItems(_ items: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.queryItems = (components.queryItems ?? []) + items
        return components.url ?? self
    }
}
