import Foundation
import Observation

struct WebDAVConfiguration: Codable, Hashable {
    var baseURL: URL
    var username: String
}

@MainActor
@Observable
final class WebDAVService: NSObject {
    private let api: APIClient
    private let secrets: SecretStore
    private let persistence: PersistenceStore
    private(set) var configuration: WebDAVConfiguration?

    init(api: APIClient, secrets: SecretStore, persistence: PersistenceStore) {
        self.api = api
        self.secrets = secrets
        self.persistence = persistence
        self.configuration = persistence.load(WebDAVConfiguration.self, for: .webDAVConfiguration)
    }

    func configure(url: URL, username: String, password: String) async throws {
        try URLSafetyPolicy.validate(url, credentialBearing: true)
        let configuration = WebDAVConfiguration(baseURL: url, username: username)
        try secrets.set(password, for: "webdav.password")
        self.configuration = configuration
        persistence.save(configuration, for: .webDAVConfiguration)
        _ = try await list(path: "")
    }

    func disconnect() throws {
        try secrets.remove("webdav.password")
        configuration = nil
        persistence.remove(.webDAVConfiguration)
    }

    func list(path: String) async throws -> [WebDAVEntry] {
        guard let configuration, let password = try secrets.get("webdav.password") else { throw ProviderError.missingCredential }
        let target = path.isEmpty ? configuration.baseURL : configuration.baseURL.appending(path: path)
        let auth = Data("\(configuration.username):\(password)".utf8).base64EncodedString()
        let data = try await api.data(APIRequest(url: target, method: "PROPFIND", headers: ["Authorization": "Basic \(auth)", "Depth": "1", "Content-Type": "application/xml"], body: Data("<?xml version=\"1.0\"?><propfind xmlns=\"DAV:\"><prop><displayname/><resourcetype/><getcontentlength/><getcontenttype/></prop></propfind>".utf8), credentialBearing: true))
        return WebDAVXMLParser.parse(data: data).dropFirst().map { $0 }
    }

    func streamURL(for entry: WebDAVEntry) throws -> URL {
        guard let base = configuration?.baseURL, let url = URL(string: entry.href, relativeTo: base)?.absoluteURL else { throw NetworkPolicyError.invalidURL }
        try URLSafetyPolicy.validate(url, credentialBearing: true)
        return url
    }

    func streamSource(for entry: WebDAVEntry) throws -> StreamSource {
        guard let configuration, let password = try secrets.get("webdav.password") else { throw ProviderError.missingCredential }
        let url = try streamURL(for: entry)
        let auth = Data("\(configuration.username):\(password)".utf8).base64EncodedString()
        return StreamSource(id: "webdav:\(entry.href)", name: entry.name, url: url, provider: "WebDAV", headers: ["Authorization": "Basic \(auth)"])
    }
}

private final class WebDAVXMLParser: NSObject, XMLParserDelegate {
    private var entries: [WebDAVEntry] = []
    private var current: [String: String] = [:]
    private var text = ""
    private var inResponse = false

    static func parse(data: Data) -> [WebDAVEntry] {
        let delegate = WebDAVXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = elementName.components(separatedBy: ":").last?.lowercased() ?? elementName
        if name == "response" { inResponse = true; current = [:] }
        text = ""
        if inResponse, name == "collection" { current["collection"] = "true" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.components(separatedBy: ":").last?.lowercased() ?? elementName
        if inResponse, ["href", "displayname", "getcontentlength", "getcontenttype"].contains(name) {
            current[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if name == "response" {
            let href = current["href"] ?? ""
            let fallback = href.removingPercentEncoding?.split(separator: "/").last.map(String.init) ?? "Folder"
            entries.append(WebDAVEntry(name: current["displayname"] ?? fallback, href: href, isDirectory: current["collection"] == "true", contentLength: current["getcontentlength"].flatMap(Int64.init), contentType: current["getcontenttype"]))
            inResponse = false
        }
        text = ""
    }
}
