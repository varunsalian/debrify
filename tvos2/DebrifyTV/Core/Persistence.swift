import Foundation

enum PersistenceKey: String {
    case playlist
    case continueWatching
    case favorites
    case addons
    case webDAVConfiguration
    case xtreamConfiguration
    case playbackPreferences
    case cinemetaSeeded
}

struct PlaybackPreferences: Codable, Equatable, Sendable {
    var alwaysOpenInInfuse = false
}

protocol PersistenceStore: AnyObject {
    func save<T: Encodable>(_ value: T, for key: PersistenceKey)
    func load<T: Decodable>(_ type: T.Type, for key: PersistenceKey) -> T?
    func remove(_ key: PersistenceKey)
}

final class UserDefaultsPersistenceStore: PersistenceStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func save<T: Encodable>(_ value: T, for key: PersistenceKey) {
        if let data = try? encoder.encode(value) { defaults.set(data, forKey: key.rawValue) }
    }

    func load<T: Decodable>(_ type: T.Type, for key: PersistenceKey) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    func remove(_ key: PersistenceKey) { defaults.removeObject(forKey: key.rawValue) }
}
