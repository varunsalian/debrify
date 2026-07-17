import XCTest
@testable import DebrifyTV

final class SecureAddonStoreTests: XCTestCase {
    func testPersonalizedAddonURLIsAbsentFromOrdinaryPreferences() throws {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let addon = personalizedAddon()

        try fixture.store.save([addon])

        let persisted = try XCTUnwrap(fixture.defaults.data(forKey: PersistenceKey.addons.rawValue))
        let plaintext = String(decoding: persisted, as: UTF8.self)
        XCTAssertFalse(plaintext.contains("private-user-token"))
        XCTAssertFalse(plaintext.contains("secret.example"))
        XCTAssertFalse(plaintext.contains("baseURL"))
        XCTAssertFalse(fixture.secrets.values.isEmpty)
        XCTAssertEqual(fixture.store.load(), [addon])
    }

    func testLegacyPlaintextAddonIsMigratedAndOverwritten() throws {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let addon = personalizedAddon()
        fixture.persistence.save([addon], for: .addons)
        XCTAssertTrue(String(decoding: try XCTUnwrap(fixture.defaults.data(forKey: PersistenceKey.addons.rawValue)), as: UTF8.self).contains("private-user-token"))

        XCTAssertEqual(fixture.store.load(), [addon])

        let migrated = String(decoding: try XCTUnwrap(fixture.defaults.data(forKey: PersistenceKey.addons.rawValue)), as: UTF8.self)
        XCTAssertFalse(migrated.contains("private-user-token"))
        XCTAssertFalse(migrated.contains("secret.example"))
        XCTAssertNotNil(fixture.persistence.load(PersistedAddonEnvelope.self, for: .addons))
    }

    func testMigrationFailureErasesLegacyPlaintext() {
        let suite = "DebrifyTVTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = UserDefaultsPersistenceStore(defaults: defaults)
        persistence.save([personalizedAddon()], for: .addons)
        let store = SecureAddonStore(persistence: persistence, secrets: FailingSecretStore())

        XCTAssertTrue(store.load().isEmpty)
        XCTAssertNil(defaults.data(forKey: PersistenceKey.addons.rawValue))
    }

    private func personalizedAddon() -> AddonManifest {
        AddonManifest(
            id: "com.example.private",
            name: "Private addon",
            description: "Test",
            version: "1.0",
            logo: URL(string: "https://secret.example/private-user-token/logo.png"),
            baseURL: URL(string: "https://secret.example/private-user-token")!,
            catalogs: [AddonCatalog(id: "movies", type: "movie", name: "Movies", extra: nil)]
        )
    }

    private func makeFixture() -> (suite: String, defaults: UserDefaults, persistence: UserDefaultsPersistenceStore, secrets: MemorySecretStore, store: SecureAddonStore) {
        let suite = "DebrifyTVTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let persistence = UserDefaultsPersistenceStore(defaults: defaults)
        let secrets = MemorySecretStore()
        return (suite, defaults, persistence, secrets, SecureAddonStore(persistence: persistence, secrets: secrets))
    }
}

private final class MemorySecretStore: SecretStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func set(_ value: String, for key: String) throws { values[key] = value }
    func get(_ key: String) throws -> String? { values[key] }
    func remove(_ key: String) throws { values.removeValue(forKey: key) }
}

private struct FailingSecretStore: SecretStore {
    struct Failure: Error {}
    func set(_ value: String, for key: String) throws { throw Failure() }
    func get(_ key: String) throws -> String? { nil }
    func remove(_ key: String) throws {}
}
