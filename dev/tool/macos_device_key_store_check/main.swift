// Behaviour checks for macos/Runner/MacOsDeviceKeyStore.swift. Standalone so it
// never launches the app or touches a real install's container. Run with:
//
//   swiftc macos/Runner/MacOsDeviceKeyStore.swift \
//     dev/tool/macos_device_key_store_check/main.swift -o /tmp/key_store_check
//   /tmp/key_store_check
import Foundation
import Security

final class FakeLegacy: LegacyDeviceKeySource {
  var value: Data?
  var denied = false
  var reads = 0
  var deletes = 0
  init(_ value: Data? = nil) { self.value = value }
  func read() throws -> Data? {
    reads += 1
    if denied { throw DeviceSecretError.keychainDenied }
    return value
  }
  func delete() { deletes += 1 }
}

var failures = 0
func check(_ condition: Bool, _ name: String) {
  if !condition { failures += 1 }
  print("\(condition ? "ok  " : "FAIL") \(name)")
}
func throwsError(_ expected: DeviceSecretError, _ body: () throws -> Void) -> Bool {
  do { try body(); return false } catch let error as DeviceSecretError { return error == expected } catch { return false }
}

let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("key-store-\(UUID().uuidString)")
var index = 0
func freshDirectory() -> URL {
  index += 1
  return root.appendingPathComponent("case\(index)")
}
func keyFile(_ directory: URL) -> URL { directory.appendingPathComponent("device-key-v1") }
let oldKey = Data(repeating: 7, count: 32)

do {
  let directory = freshDirectory()
  let legacy = FakeLegacy()
  let created = try MacOsDeviceKeyStore(directory: directory, legacy: legacy).key(allowCreate: true)
  check(created.count == 32, "fresh install creates a 32-byte key")
  let attributes = try FileManager.default.attributesOfItem(atPath: keyFile(directory).path)
  check((attributes[.posixPermissions] as? Int) == 0o600, "key file is private to the user")
  let reopened = try MacOsDeviceKeyStore(directory: directory, legacy: legacy).key(allowCreate: false)
  check(reopened == created, "key survives a relaunch")
  check(legacy.reads == 1, "keychain is not consulted once the file exists")
}

do {
  let directory = freshDirectory()
  let store = MacOsDeviceKeyStore(directory: directory, legacy: FakeLegacy())
  check(throwsError(.missing) { _ = try store.key(allowCreate: false) }, "no key and allowCreate false reports missing")
  check(!FileManager.default.fileExists(atPath: keyFile(directory).path), "missing key is not minted")
}

do {
  let directory = freshDirectory()
  let legacy = FakeLegacy(oldKey)
  let migrated = try MacOsDeviceKeyStore(directory: directory, legacy: legacy).key(allowCreate: false)
  check(migrated == oldKey, "migration keeps the existing key bytes")
  check(try Data(contentsOf: keyFile(directory)) == oldKey, "migration writes the same key to the file")
  legacy.value = Data(repeating: 9, count: 32)
  let later = try MacOsDeviceKeyStore(directory: directory, legacy: legacy).key(allowCreate: true)
  check(later == oldKey && legacy.reads == 1, "the prompt happens only on the migrating launch")
  try FileManager.default.removeItem(at: keyFile(directory))
  legacy.value = oldKey
  let recovered = try MacOsDeviceKeyStore(directory: directory, legacy: legacy).key(allowCreate: false)
  check(recovered == oldKey, "a lost file recovers from the keychain item")
}

do {
  let directory = freshDirectory()
  let legacy = FakeLegacy(oldKey)
  legacy.denied = true
  let store = MacOsDeviceKeyStore(directory: directory, legacy: legacy)
  check(throwsError(.keychainDenied) { _ = try store.key(allowCreate: true) }, "Deny is reported even when creation is allowed")
  check(!FileManager.default.fileExists(atPath: keyFile(directory).path), "Deny never mints a replacement key")
  legacy.denied = false
  check(try store.key(allowCreate: false) == oldKey, "retry after Deny migrates in the same process")
}

do {
  let directory = freshDirectory()
  try FileManager.default.createDirectory(at: keyFile(directory), withIntermediateDirectories: true)
  let legacy = FakeLegacy()
  var threw = false
  do { _ = try MacOsDeviceKeyStore(directory: directory, legacy: legacy).key(allowCreate: true) } catch { threw = true }
  check(threw && legacy.reads == 0, "a read error is not treated as a missing key")
}

do {
  let directory = freshDirectory()
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try Data(repeating: 1, count: 5).write(to: keyFile(directory))
  let store = MacOsDeviceKeyStore(directory: directory, legacy: FakeLegacy(oldKey))
  check(throwsError(.unreadable) { _ = try store.key(allowCreate: true) }, "a damaged key file reports unreadable")
  check(try Data(contentsOf: keyFile(directory)).count == 5, "a damaged key file is not overwritten")
}

do {
  let directory = freshDirectory()
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
  defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
  let legacy = FakeLegacy(oldKey)
  let store = MacOsDeviceKeyStore(directory: directory, legacy: legacy)
  let first = try store.key(allowCreate: false)
  let second = try store.key(allowCreate: false)
  check(first == oldKey && second == oldKey, "a failed copy still opens the app with the existing key")
  check(legacy.reads == 1, "a failed copy does not re-prompt on every operation")
  check(store.keyCopyDeferred, "a failed copy is reported")
  let fresh = MacOsDeviceKeyStore(directory: directory, legacy: FakeLegacy())
  var threw = false
  do { _ = try fresh.key(allowCreate: true) } catch { threw = true }
  check(threw, "a new key that cannot be saved is an error")
}

do {
  let directory = freshDirectory()
  let legacy = FakeLegacy(oldKey)
  let store = MacOsDeviceKeyStore(directory: directory, legacy: legacy)
  _ = try store.key(allowCreate: false)
  try store.destroy()
  try store.destroy()
  check(!FileManager.default.fileExists(atPath: keyFile(directory).path), "erase removes the key file and can repeat")
  check(legacy.deletes == 2, "erase attempts to delete the keychain item")
  let next = MacOsDeviceKeyStore(directory: directory, legacy: legacy)
  let reads = legacy.reads
  check(throwsError(.missing) { _ = try next.key(allowCreate: false) }, "after erase the old key is not resurrected")
  let created = try next.key(allowCreate: true)
  check(created != oldKey && legacy.reads == reads, "after erase a new key is made without a keychain prompt")
}

do {
  let directory = freshDirectory()
  let lock = NSLock()
  var keys: [Data] = []
  DispatchQueue.concurrentPerform(iterations: 16) { _ in
    let store = MacOsDeviceKeyStore(directory: directory, legacy: FakeLegacy())
    if let key = try? store.key(allowCreate: true) {
      lock.lock(); keys.append(key); lock.unlock()
    }
  }
  check(keys.count == 16 && Set(keys).count == 1, "concurrent creators converge on one key")
  let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".device-key-") }
  check(leftovers.isEmpty, "no temporary key files are left behind")
}

for status in [errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed] {
  check(KeychainLegacyDeviceKeySource.isAccessRefusal(status), "status \(status) can be retried")
}
for status in [errSecNoDefaultKeychain, errSecNotAvailable, errSecInternalComponent, errSecItemNotFound] {
  check(!KeychainLegacyDeviceKeySource.isAccessRefusal(status), "status \(status) is not a refusal")
}

try? FileManager.default.removeItem(at: root)
print(failures == 0 ? "All checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
