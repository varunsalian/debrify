import Foundation
import Security

enum DeviceSecretError: Error {
  case missing
  case unreadable
  case keychainDenied
}

/// The login-keychain item that held the device key before it moved to a file.
protocol LegacyDeviceKeySource {
  /// Returns nil only when the item does not exist.
  func read() throws -> Data?
  func delete()
}

/// macOS ties a login-keychain item to the signature of the build that wrote
/// it. Releases are ad-hoc signed, so every update has a new signature and the
/// system asks for the login password again. A later build also cannot delete
/// the item (errSecInvalidOwnerEdit), so `delete` is best effort.
final class KeychainLegacyDeviceKeySource: LegacyDeviceKeySource {
  private let service: String
  private let account: String

  init(
    service: String = "com.debrify.app.profile-device-secret",
    account: String = "device-key-v1"
  ) {
    self.service = service
    self.account = account
  }

  private var itemQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
    ]
  }

  func read() throws -> Data? {
    var query = itemQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    if Self.isAccessRefusal(status) { throw DeviceSecretError.keychainDenied }
    guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    guard let data = item as? Data else { throw DeviceSecretError.unreadable }
    return data
  }

  func delete() {
    _ = SecItemDelete(itemQuery as CFDictionary)
  }

  /// The statuses a retry can fix because the user can release the key: Deny,
  /// cancel, a wrong password, or a locked keychain.
  static func isAccessRefusal(_ status: OSStatus) -> Bool {
    status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed
  }
}

/// Owns the device key as a private file in the app's sandbox container.
///
/// Credentials already sealed with the keychain key must stay readable, so the
/// first launch after this change copies that key here unchanged. The keychain
/// item stays behind as a fallback in case the file is ever lost, and is never
/// consulted again while the file exists. Holding the key outside the keychain
/// is the documented exception in AGENTS.md for ad-hoc signed macOS releases.
final class MacOsDeviceKeyStore {
  static let keyLength = 32

  private let directory: URL
  private let legacy: LegacyDeviceKeySource
  private var cachedKey: Data?
  /// The legacy key opened but could not be copied, so the next launch asks again.
  private(set) var keyCopyDeferred = false

  private var keyFile: URL { directory.appendingPathComponent("device-key-v1") }
  /// Written by `destroy`. The app usually cannot delete the keychain item, so
  /// without this an erased install would be prompted for the old key again.
  private var legacyRetiredMarker: URL {
    directory.appendingPathComponent("legacy-keychain-retired")
  }

  init(directory: URL, legacy: LegacyDeviceKeySource) {
    self.directory = directory
    self.legacy = legacy
  }

  static func defaultDirectory() -> URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return root
      .appendingPathComponent(Bundle.main.bundleIdentifier ?? "debrify", isDirectory: true)
      .appendingPathComponent("device-secret", isDirectory: true)
  }

  func key(allowCreate: Bool) throws -> Data {
    if let cachedKey { return cachedKey }
    // Any read failure other than "no such file" throws here. Falling through
    // would mint a new key over credentials sealed with the existing one.
    if let stored = try readKeyFile() {
      cachedKey = stored
      return stored
    }
    if !FileManager.default.fileExists(atPath: legacyRetiredMarker.path),
       let migrated = try legacy.read() {
      guard migrated.count == Self.keyLength else { throw DeviceSecretError.unreadable }
      // The key is valid even if the copy fails, so this launch carries on and
      // the next one retries. Caching avoids re-prompting on every operation.
      do {
        cachedKey = try persist(migrated)
      } catch {
        keyCopyDeferred = true
        NSLog("Debrify device key copy deferred: %@ %d", (error as NSError).domain, (error as NSError).code)
        cachedKey = migrated
      }
      return cachedKey!
    }
    guard allowCreate else { throw DeviceSecretError.missing }
    let effective = try persist(try Self.randomKey())
    cachedKey = effective
    return effective
  }

  func destroy() throws {
    try prepareDirectory()
    // Marker first: a crash before the key is removed leaves a working file.
    if !FileManager.default.createFile(atPath: legacyRetiredMarker.path, contents: Data()) {
      throw Self.posixError()
    }
    if unlink(keyFile.path) != 0 && errno != ENOENT { throw Self.posixError() }
    legacy.delete()
    cachedKey = nil
  }

  private func readKeyFile() throws -> Data? {
    let data: Data
    do {
      data = try Data(contentsOf: keyFile)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
      return nil
    }
    guard data.count == Self.keyLength else { throw DeviceSecretError.unreadable }
    return data
  }

  /// Writes without ever replacing an existing key. Returns the key that ended
  /// up on disk, which is the other writer's if a second process got there first.
  private func persist(_ key: Data) throws -> Data {
    try prepareDirectory()
    let temporary = directory.appendingPathComponent(".device-key-\(UUID().uuidString)")
    defer { unlink(temporary.path) }
    try writeDurably(key, to: temporary)
    // link(2) fails rather than replaces, so an existing key can never be lost.
    if link(temporary.path, keyFile.path) != 0 && errno != EEXIST { throw Self.posixError() }
    syncDirectory()
    guard let stored = try readKeyFile() else { throw DeviceSecretError.missing }
    return stored
  }

  private func prepareDirectory() throws {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
  }

  private func writeDurably(_ key: Data, to url: URL) throws {
    let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw Self.posixError() }
    defer { close(descriptor) }
    let written = key.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    guard written == key.count else { throw Self.posixError() }
    if fcntl(descriptor, F_FULLFSYNC) != 0 && fsync(descriptor) != 0 { throw Self.posixError() }
  }

  private func syncDirectory() {
    let descriptor = open(directory.path, O_RDONLY | O_CLOEXEC)
    guard descriptor >= 0 else { return }
    defer { close(descriptor) }
    _ = fsync(descriptor)
  }

  private static func randomKey() throws -> Data {
    var bytes = Data(count: keyLength)
    let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, keyLength, $0.baseAddress!) }
    guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    return bytes
  }

  private static func posixError() -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
  }
}
