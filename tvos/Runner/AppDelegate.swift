import UIKit
import Flutter
import TVServices
import AVFoundation
import CryptoKit
import Security

private final class TvOsDeviceSecretCipher {
    private let service = "com.varunsalian.debrifytv.profile-device-secret"
    private let account = "device-key-v1"

    func install(on messenger: FlutterBinaryMessenger) -> FlutterMethodChannel {
        let channel = FlutterMethodChannel(name: "debrify/device_secret", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(FlutterError(code: "unavailable", message: nil, details: nil)); return }
            do {
                switch call.method {
                case "initialize": _ = try self.key(); result(true)
                case "seal":
                    let (input, aad) = try self.arguments(call)
                    let box = try AES.GCM.seal(input, using: try self.key(), authenticating: aad)
                    guard let combined = box.combined else { throw NSError(domain: "DeviceSecret", code: 2) }
                    result(combined.base64EncodedString())
                case "open":
                    let (input, aad) = try self.arguments(call, payloadName: "envelope")
                    let box = try AES.GCM.SealedBox(combined: input)
                    result(try AES.GCM.open(box, using: try self.key(), authenticating: aad).base64EncodedString())
                case "destroy": try self.destroy(); result(nil)
                default: result(FlutterMethodNotImplemented)
                }
            } catch {
                result(FlutterError(code: "device_secret_failed", message: error.localizedDescription, details: nil))
            }
        }
        return channel
    }

    private func destroy() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func arguments(_ call: FlutterMethodCall, payloadName: String = "plaintext") throws -> (Data, Data) {
        guard let args = call.arguments as? [String: Any],
              let value = args[payloadName] as? String,
              let input = Data(base64Encoded: value),
              let aadValue = args["associatedData"] as? String,
              let aad = Data(base64Encoded: aadValue) else {
            throw NSError(domain: "DeviceSecret", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid channel arguments"])
        }
        return (input, aad)
    }

    private func key() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard randomStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(randomStatus)) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: bytes,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus)) }
        return SymmetricKey(data: bytes)
    }
}

private final class TvOsProfileRecoveryChannel {
    private let service = "com.varunsalian.debrifytv.profile-recovery"
    private let manifestAccount = "published-manifest-v1"
    private let installMarkerKey = "debrify.profileRecovery.installInstanceId.v1"
    private let shardBytes = 8 * 1024
    private let maxEnvelopeBytes = 768 * 1024

    // ── Mirror (2026-08-20 incident) ────────────────────────────────────────
    // tvOS purged all ten 8KB shards of a committed generation while keeping
    // the 1KB manifest — no app code path can produce that state (the sweep
    // only ever deletes accounts absent from the manifest it just verified),
    // so the Keychain alone is not durable enough to be the sole authority
    // here. NSUserDefaults is the one store tvOS documents as persistent
    // (500KB budget), so every publication also lands there as an encrypted,
    // zlib-compressed mirror, and a failed Keychain read heals from it
    // silently instead of sending the user to the recovery screen. The AES
    // key is derived (see mirrorSymmetricKey), never stored — a stored key
    // would be subject to the very loss the mirror guards against. If BOTH
    // stores are lost, behavior is unchanged from before: recovery screen.
    private var mirrorDefaultsKey: String { "\(service).mirror.v1" }
    /// Durable high-water mark of the generation counter, maintained on every
    /// successful Keychain publication — including ones whose mirror write is
    /// skipped or fails. It anchors two guarantees the Keychain alone cannot:
    /// [publish] never mints a generation below it (numbering stays monotonic
    /// across a full-service wipe, where the manifest-derived counter would
    /// restart at 1), and [usableMirror] can refuse a stale mirror even when
    /// the manifest that would prove staleness was purged with everything
    /// else. Cleared only by [clear].
    private var generationFloorKey: String { "\(service).generation-floor.v1" }
    /// Budget guard: the raw envelope is capped at 768KB, but the DEFAULTS
    /// budget is ~500KB for the WHOLE app — a mirror is skipped (with a log),
    /// never truncated, when its sealed form would crowd that. The stored
    /// footprint is ≈ 4/3 × sealed (the payload is base64 inside the JSON
    /// document), so 192KB sealed ≈ 256KB stored, leaving the other half of
    /// the budget to the app's own preferences. A real envelope observed in
    /// production sealed to ~35KB.
    private let mirrorMaxSealedBytes = 192 * 1024

    func install(on messenger: FlutterBinaryMessenger) -> FlutterMethodChannel {
        let channel = FlutterMethodChannel(name: "debrify/tvos_profile_recovery", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(FlutterError(code: "unavailable", message: nil, details: nil)); return }
            do {
                switch call.method {
                case "read": result(try self.read())
                case "publish":
                    guard let source = call.arguments as? String,
                          let data = source.data(using: .utf8),
                          data.count <= self.maxEnvelopeBytes else {
                        throw NSError(domain: "ProfileRecovery", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recovery envelope is invalid or too large"])
                    }
                    try self.publish(data)
                    result(true)
                case "clear": try self.clear(); result(nil)
                default: result(FlutterMethodNotImplemented)
                }
            } catch {
                result(FlutterError(code: "profile_recovery_failed", message: error.localizedDescription, details: nil))
            }
        }
        return channel
    }

    private func installMarker(create: Bool) throws -> String? {
        let defaults = UserDefaults.standard
        if let current = defaults.string(forKey: installMarkerKey), !current.isEmpty { return current }
        guard create else { return nil }
        let value = UUID().uuidString.lowercased()
        defaults.set(value, forKey: installMarkerKey)
        guard defaults.synchronize() else {
            throw NSError(domain: "ProfileRecovery", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not publish install marker"])
        }
        return value
    }

    private func publish(_ data: Data) throws {
        let marker = try installMarker(create: true)!
        let oldManifest = try keychainRead(manifestAccount).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let generation = max(
            (oldManifest?["generation"] as? Int) ?? 0,
            UserDefaults.standard.integer(forKey: generationFloorKey)) + 1
        // A generation counter alone is not a safe shard namespace: a crash
        // before manifest publication leaves immutable N+1 shards behind and a
        // retry would select N+1 again. The transaction UUID makes every retry
        // independent while the manifest remains the sole visibility point.
        let transaction = UUID().uuidString.lowercased()
        var hashes: [String] = []
        var accounts: [String] = []
        var offset = 0
        var index = 0
        while offset < data.count {
            let end = min(offset + shardBytes, data.count)
            let shard = data.subdata(in: offset..<end)
            let account = "generation.\(generation).tx.\(transaction).shard.\(index)"
            try keychainAddImmutable(account, data: shard)
            guard try keychainRead(account) == shard else {
                throw NSError(domain: "ProfileRecovery", code: 3, userInfo: [NSLocalizedDescriptionKey: "Recovery shard verification failed"])
            }
            accounts.append(account)
            hashes.append(Data(SHA256.hash(data: shard)).base64EncodedString())
            offset = end
            index += 1
        }
        let manifest: [String: Any] = [
            "version": 1,
            "installInstanceId": marker,
            "generation": generation,
            "length": data.count,
            "accounts": accounts,
            "hashes": hashes,
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try keychainUpsert(manifestAccount, data: manifestData)
        guard try keychainRead(manifestAccount) == manifestData else {
            throw NSError(domain: "ProfileRecovery", code: 4, userInfo: [NSLocalizedDescriptionKey: "Recovery manifest verification failed"])
        }
        // The floor advances the instant the publication is durable — before
        // the sweep and the mirror write, both of which may fail. Anything
        // later and a failure in between leaves a committed generation the
        // floor does not know about, which is precisely the gap that lets a
        // retained older mirror pass the freshness check after a purge.
        if generation > UserDefaults.standard.integer(forKey: generationFloorKey) {
            UserDefaults.standard.set(generation, forKey: generationFloorKey)
        }
        // A terminated pre-manifest transaction is invisible but its immutable
        // shards can remain. Once a new manifest is verified, sweep every
        // unreferenced recovery shard (including those abandoned transactions)
        // so repeated interruption cannot grow Keychain without bound.
        for account in try keychainAccounts()
            where account.hasPrefix("generation.") && !accounts.contains(account) {
            try? keychainDelete(account)
        }
        writeMirror(data, generation: generation, marker: marker)
    }

    private func read() throws -> String? {
        do {
            if let primary = try readPrimary() {
                let current = manifestGeneration() ?? 0
                let floor = UserDefaults.standard.integer(forKey: generationFloorKey)
                // A readable envelope is not automatically the NEWEST one: if
                // the Keychain itself rolled back beneath the committed floor
                // (the incident that motivated all of this was a partial
                // Keychain loss), importing it would silently undo committed
                // profile state. Prefer a mirror at or above the floor; with
                // neither copy current, fail to the recovery screen rather
                // than time-travel.
                if current < floor {
                    if let marker = try? installMarker(create: false),
                       let mirrored = usableMirror(marker: marker) {
                        NSLog("[ProfileRecovery] Keychain envelope generation %ld predates committed %ld; restoring newer mirror",
                              current, floor)
                        heal(mirrored)
                        return mirrored
                    }
                    throw NSError(domain: "ProfileRecovery", code: 9, userInfo: [NSLocalizedDescriptionKey: "Recovery envelope predates committed state"])
                }
                // An upgraded install has no mirror until its next Keychain
                // publication, and a corrupt mirror or one left behind by a
                // failed write is worse than none — it would never repair
                // itself while the primary stays healthy. Reseed whenever the
                // mirror is not both readable and current; while the primary
                // is readable it is the authority, so overwriting is safe.
                if let marker = try? installMarker(create: false) {
                    let existing = readMirror(marker: marker)
                    if existing == nil || existing!.generation < current {
                        writeMirror(Data(primary.utf8), generation: current, marker: marker)
                    }
                }
                return primary
            }
            // Manifest absent. A fresh install and a post-`clear` state have
            // no marker and no mirror and correctly fall through to nil; a
            // purge that took the whole service can still heal from the
            // mirror.
            guard let marker = try installMarker(create: false),
                  let mirrored = usableMirror(marker: marker) else { return nil }
            NSLog("[ProfileRecovery] Keychain envelope missing; restoring from mirror")
            heal(mirrored)
            return mirrored
        } catch {
            guard let marker = try? installMarker(create: false),
                  let mirrored = usableMirror(marker: marker) else { throw error }
            NSLog("[ProfileRecovery] Keychain envelope unreadable (%@); restoring from mirror",
                  error.localizedDescription)
            heal(mirrored)
            return mirrored
        }
    }

    /// The mirror's envelope, unless something newer proves it stale.
    ///
    /// A mirror write can be skipped (size cap) or fail while the Keychain
    /// publication succeeded, leaving the mirror generations behind. Healing
    /// from it would silently roll the registry back — resurrecting deleted
    /// profiles or an old PIN. The floor is the newest generation known to
    /// have committed: a surviving manifest's counter, or the durable
    /// high-water mark when the manifest was purged too. An older mirror is
    /// refused and the caller falls through to the recovery screen rather
    /// than time-travel.
    private func usableMirror(marker: String) -> String? {
        guard let mirrored = readMirror(marker: marker) else { return nil }
        let floor = max(
            manifestGeneration() ?? 0,
            UserDefaults.standard.integer(forKey: generationFloorKey))
        if mirrored.generation < floor {
            NSLog("[ProfileRecovery] Mirror refused: generation %ld predates committed %ld",
                  mirrored.generation, floor)
            return nil
        }
        return mirrored.text
    }

    private func manifestGeneration() -> Int? {
        guard let manifestData = try? keychainRead(manifestAccount),
              let manifest = (try? JSONSerialization.jsonObject(with: manifestData)) as? [String: Any] else {
            return nil
        }
        return manifest["generation"] as? Int
    }

    /// Republishes a mirror-recovered envelope back into the Keychain so the
    /// primary is whole again. Failure is logged, not thrown — the caller
    /// already holds a good envelope, and the next successful publication
    /// repairs the Keychain anyway.
    private func heal(_ text: String) {
        do {
            try publish(Data(text.utf8))
            NSLog("[ProfileRecovery] Keychain re-published from mirror")
        } catch {
            NSLog("[ProfileRecovery] Self-heal republication failed: %@",
                  error.localizedDescription)
        }
    }

    private func readPrimary() throws -> String? {
        guard let manifestData = try keychainRead(manifestAccount) else { return nil }
        guard let marker = try installMarker(create: false) else {
            throw NSError(domain: "ProfileRecovery", code: 5, userInfo: [NSLocalizedDescriptionKey: "Recovery state exists without this installation marker"])
        }
        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              manifest["version"] as? Int == 1,
              manifest["installInstanceId"] as? String == marker,
              let length = manifest["length"] as? Int,
              let accounts = manifest["accounts"] as? [String],
              let hashes = manifest["hashes"] as? [String],
              accounts.count == hashes.count,
              accounts.count <= maxEnvelopeBytes / shardBytes + 1 else {
            throw NSError(domain: "ProfileRecovery", code: 6, userInfo: [NSLocalizedDescriptionKey: "Recovery manifest is corrupt or belongs to another installation"])
        }
        var combined = Data()
        for (index, account) in accounts.enumerated() {
            guard let shard = try keychainRead(account),
                  Data(SHA256.hash(data: shard)).base64EncodedString() == hashes[index] else {
                throw NSError(domain: "ProfileRecovery", code: 7, userInfo: [NSLocalizedDescriptionKey: "Recovery generation is incomplete"])
            }
            combined.append(shard)
        }
        guard combined.count == length, combined.count <= maxEnvelopeBytes,
              let text = String(data: combined, encoding: .utf8) else {
            throw NSError(domain: "ProfileRecovery", code: 8, userInfo: [NSLocalizedDescriptionKey: "Recovery payload is invalid"])
        }
        return text
    }

    private func clear() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        // The mirror dies with the service — a cleared device must not
        // resurrect profiles through the fallback path. (Its key is derived,
        // not stored, so there is nothing key-shaped to delete.) The
        // generation floor resets too: after a deliberate reset, restarting
        // the counter at 1 is correct, unlike after a purge.
        UserDefaults.standard.removeObject(forKey: mirrorDefaultsKey)
        UserDefaults.standard.removeObject(forKey: generationFloorKey)
        UserDefaults.standard.removeObject(forKey: installMarkerKey)
    }

    private func keychainRead(_ account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return data
    }

    private func keychainAccounts() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        let records: [[String: Any]]
        if let list = item as? [[String: Any]] {
            records = list
        } else if let record = item as? [String: Any] {
            records = [record]
        } else {
            return []
        }
        return records.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func keychainAddImmutable(_ account: String, data: Data) throws {
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    private func keychainUpsert(_ account: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound { try keychainAddImmutable(account, data: data); return }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    private func keychainDelete(_ account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    /// Derived, never stored. An earlier design kept a random key as its own
    /// Keychain item — but the mirror exists precisely to survive Keychain
    /// loss, and a purge that took the whole service would have taken the key
    /// with it, leaving a perfectly good mirror permanently undecryptable.
    /// `identifierForVendor` has exactly the right lifetime: stable across
    /// updates and Keychain purges, gone on uninstall (when the defaults die
    /// too). The mirror still never leaves the device readable — the
    /// identifier is not stored alongside the ciphertext.
    private func mirrorSymmetricKey() throws -> SymmetricKey {
        guard let vendor = UIDevice.current.identifierForVendor?.uuidString else {
            throw NSError(domain: "ProfileRecovery", code: 22, userInfo: [NSLocalizedDescriptionKey: "Device identifier unavailable for mirror key"])
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(vendor.utf8)),
            salt: Data(service.utf8),
            info: Data("debrify.profile-recovery.mirror-key.v3".utf8),
            outputByteCount: 32)
    }

    /// The generation is part of the AAD, not just the plaintext document —
    /// so a rolled-back or hand-edited generation field fails authentication
    /// instead of steering the freshness check in [read].
    private func mirrorAAD(marker: String, generation: Int) -> Data {
        Data("\(service)|\(marker)|mirror-v3|gen.\(generation)".utf8)
    }

    /// Non-fatal by design: the Keychain publication this shadows has already
    /// verified, and a missing mirror only means the NEXT purge is unhealed —
    /// the same exposure as before the mirror existed, never worse.
    private func writeMirror(_ data: Data, generation: Int, marker: String) {
        do {
            let compressed = try (data as NSData).compressed(using: .zlib) as Data
            let sealed = try AES.GCM.seal(
                compressed,
                using: try mirrorSymmetricKey(),
                authenticating: mirrorAAD(marker: marker, generation: generation))
            guard let combined = sealed.combined else {
                throw NSError(domain: "ProfileRecovery", code: 20)
            }
            guard combined.count <= mirrorMaxSealedBytes else {
                NSLog("[ProfileRecovery] Mirror skipped: %ld sealed bytes exceeds the defaults budget",
                      combined.count)
                return
            }
            let document: [String: Any] = [
                "version": 3,
                "generation": generation,
                "length": data.count,
                "payload": combined.base64EncodedString(),
            ]
            let json = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
            guard let text = String(data: json, encoding: .utf8) else {
                throw NSError(domain: "ProfileRecovery", code: 21)
            }
            // Stored as the JSON string itself — an extra base64 pass over the
            // whole document would inflate the defaults footprint by another
            // third for nothing (the sealed payload inside is already base64).
            UserDefaults.standard.set(text, forKey: mirrorDefaultsKey)
        } catch {
            NSLog("[ProfileRecovery] Mirror write failed (non-fatal): %@",
                  error.localizedDescription)
        }
    }

    /// nil on any imperfection — a mirror that fails authentication, inflation,
    /// or the length check is treated as absent, never partially trusted.
    private func readMirror(marker: String) -> (text: String, generation: Int)? {
        guard let stored = UserDefaults.standard.string(forKey: mirrorDefaultsKey),
              let json = stored.data(using: .utf8),
              let document = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              document["version"] as? Int == 3,
              let generation = document["generation"] as? Int,
              let length = document["length"] as? Int,
              length <= maxEnvelopeBytes,
              let payload = document["payload"] as? String,
              let combined = Data(base64Encoded: payload) else { return nil }
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            let compressed = try AES.GCM.open(
                box,
                using: try mirrorSymmetricKey(),
                authenticating: mirrorAAD(marker: marker, generation: generation))
            let data = try (compressed as NSData).decompressed(using: .zlib) as Data
            guard data.count == length, let text = String(data: data, encoding: .utf8) else {
                return nil
            }
            return (text, generation)
        } catch {
            NSLog("[ProfileRecovery] Mirror unreadable: %@", error.localizedDescription)
            return nil
        }
    }
}

private enum TopShelfPreviewError: LocalizedError {
    case invalidArguments
    case appGroupUnavailable
    case noVideoTrack
    case invalidDuration
    case compositionFailed
    case exportUnavailable
    case exportFailed
    case outputInvalid

    var errorDescription: String? {
        switch self {
        case .invalidArguments: return "The preview request is invalid."
        case .appGroupUnavailable: return "The Top Shelf App Group is unavailable."
        case .noVideoTrack: return "The trailer has no usable video track."
        case .invalidDuration: return "The trailer duration is invalid."
        case .compositionFailed: return "The trailer tracks could not be combined."
        case .exportUnavailable: return "The trailer cannot be exported as an MP4."
        case .exportFailed: return "The trailer export failed."
        case .outputInvalid: return "The cached trailer file is invalid."
        }
    }
}

private final class TvOsProfilePrivacyController {
    var sensitive = false
    private var cover: UIView?

    func install(on messenger: FlutterBinaryMessenger) -> FlutterMethodChannel {
        let channel = FlutterMethodChannel(
            name: "com.debrify.app/profile_privacy",
            binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "setSensitive",
                  let arguments = call.arguments as? [String: Any] else {
                result(FlutterMethodNotImplemented)
                return
            }
            self?.sensitive = arguments["sensitive"] as? Bool ?? false
            result(true)
        }
        return channel
    }

    func coverIfNeeded(_ window: UIWindow?) {
        guard sensitive, cover == nil, let window else { return }
        let view = UIView(frame: window.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .black
        window.addSubview(view)
        cover = view
    }

    func uncover() {
        cover?.removeFromSuperview()
        cover = nil
    }
}

@main
class AppDelegate: FlutterAppDelegate {
    /// Retained so the channel outlives `application(_:didFinishLaunchingWithOptions:)`.
    private var logChannel: FlutterMethodChannel?
    private var keyboardChannel: FlutterMethodChannel?
    private var urlChannel: FlutterMethodChannel?
    private var systemChannel: FlutterMethodChannel?
    private var topShelfChannel: FlutterMethodChannel?
    private var deviceChannel: FlutterMethodChannel?
    private var deviceSecretChannel: FlutterMethodChannel?
    private let deviceSecretCipher = TvOsDeviceSecretCipher()
    private var profileRecoveryChannel: FlutterMethodChannel?
    private var profilePrivacyChannel: FlutterMethodChannel?
    private let profileRecovery = TvOsProfileRecoveryChannel()
    private let profilePrivacy = TvOsProfilePrivacyController()
    private var pendingTopShelfAction: [String: String]?

    private static let topShelfAppGroup = "group.com.varunsalian.debrifytv"
    private static let topShelfSnapshotPath = "Library/Caches/top-shelf-v1.json"
    private static let topShelfActionsPath = "Library/Caches/top-shelf-actions-v1.json"
    private static let topShelfPreviewDirectory = "Library/Caches/TopShelfPreviews"
    private static let topShelfPreviewMaxAge: TimeInterval = 14 * 24 * 60 * 60
    private static let topShelfPreviewMaxFiles = 6
    private static let topShelfPreviewMaxBytes: Int64 = 180 * 1024 * 1024

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let flutterViewController = FlutterViewController(project: nil, nibName: nil, bundle: nil)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = flutterViewController
        window.makeKeyAndVisible()
        self.window = window

        // tvOS reports a screen scale of 1.0, so Flutter lays out against a
        // 1920x1080 LOGICAL canvas. Android TV reports 2.0 for the same panel —
        // a 960x540 logical canvas — and every size in this app (type scale,
        // padding, card and row dimensions, focus rings) was designed against
        // that. Left at 1.0 the whole UI renders at half its intended physical
        // size: readable on a monitor at desk distance, unreadable from a sofa.
        //
        // Raising the view's contentScaleFactor makes the engine lay out
        // against 960x540 while still rasterising into the full 1920x1080
        // surface, so this costs no sharpness — same pixels, correct sizes.
        flutterViewController.view.contentScaleFactor = 2.0

        // Dart's print()/debugPrint() goes to stdout, which the device console
        // does not carry in a release build — so on real hardware every Dart
        // error, including the framework's own, is invisible. Bridge it to
        // NSLog, which `devicectl ... --console` does capture. Dart side opts in
        // (tvOS only) by reassigning debugPrint.
        let logChannel = FlutterMethodChannel(
            name: "debrify/tvlog",
            binaryMessenger: flutterViewController.binaryMessenger)
        logChannel.setMethodCallHandler { call, result in
            if call.method == "log", let message = call.arguments as? String {
                NSLog("[dart] %@", message)
                result(nil)
                return
            }
            // How many channels the CURRENT output route can actually take.
            // The player caps mpv to stereo when this is <= 2: ao_avfoundation
            // hands the route the file's native layout, and on a 2-channel
            // route (AirPods, Bluetooth, a stereo TV) the resulting 5.1 fold
            // is audibly wrong -- LFE-heavy, "like being on a bus".
            //
            // This only READS the session. It deliberately does not set a
            // category or activate anything: ao_audiounit/ao_avfoundation own
            // the session, and configuring it underneath them is what makes
            // that ownership fragile.
            if call.method == "outputChannelCount" {
                let session = AVAudioSession.sharedInstance()
                let current = session.currentRoute.outputs.first?.channels?.count ?? 0
                let maximum = session.maximumOutputNumberOfChannels
                // currentRoute can report 0 before the first activation; the
                // maximum is the stable answer, so prefer the larger.
                result(max(current, maximum))
                return
            }
            result(nil)
        }
        self.logChannel = logChannel

        // SecretVault derives its at-rest encryption key from a stable
        // per-install identifier; device_info_plus has no tvOS implementation,
        // so this is the one call it would have made. nil is a valid answer —
        // the vault falls back to pepper-only derivation.
        let deviceChannel = FlutterMethodChannel(
            name: "debrify/tvdevice",
            binaryMessenger: flutterViewController.binaryMessenger)
        deviceChannel.setMethodCallHandler { call, result in
            if call.method == "id" {
                result(UIDevice.current.identifierForVendor?.uuidString)
            } else if call.method == "physicalMemory" {
                // Installed RAM in bytes. Dart gates the heavy Home paths off
                // this: the 2-3 GB units (Apple TV HD, both 3 GB 4K
                // generations) get low-res artwork and no ambient trailer.
                // Measured, not inferred from the model string — the model
                // table already burned us once (AppleTV11,1 is 3 GB, not 4).
                result(Int64(ProcessInfo.processInfo.physicalMemory))
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
        self.deviceChannel = deviceChannel

        self.deviceSecretChannel = deviceSecretCipher.install(
            on: flutterViewController.binaryMessenger)
        self.profileRecoveryChannel = profileRecovery.install(
            on: flutterViewController.binaryMessenger)
        self.profilePrivacyChannel = profilePrivacy.install(
            on: flutterViewController.binaryMessenger)

        GeneratedPluginRegistrant.register(with: self)

        // External player launch. url_launcher has no tvOS implementation in
        // this fork, and porting it for two UIApplication calls would be the
        // long way round — the Dart side (ExternalPlayerService._TvosUrl)
        // opens Infuse/VLC through this instead. `canOpen` answers honestly
        // only for schemes listed in LSApplicationQueriesSchemes; `open`
        // reports whether tvOS accepted the launch.
        let urlChannel = FlutterMethodChannel(
            name: "debrify/tvurl",
            binaryMessenger: flutterViewController.binaryMessenger)
        urlChannel.setMethodCallHandler { call, result in
            guard let urlString = call.arguments as? String,
                  let url = URL(string: urlString) else {
                result(false)
                return
            }
            switch call.method {
            case "canOpen":
                result(UIApplication.shared.canOpenURL(url))
            case "open":
                UIApplication.shared.open(url, options: [:]) { ok in
                    result(ok)
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        self.urlChannel = urlChannel

        // Menu at the app's true root must land the user on the tvOS Home
        // Screen — but Flutter's unhandled-pop fallback (SystemNavigator.pop)
        // is a no-op here: its Darwin implementation only pops a navigation
        // controller, and this app installs the FlutterViewController as the
        // window root. UIKit's `suspend` selector does exactly what the TV
        // button does — the scene resigns and tvOS takes over. (Private
        // selector; this is a sideloaded app, App Store review is not a
        // constraint.)
        let systemChannel = FlutterMethodChannel(
            name: "debrify/tvsystem",
            binaryMessenger: flutterViewController.binaryMessenger)
        systemChannel.setMethodCallHandler { call, result in
            if call.method == "suspend" {
                DispatchQueue.main.async {
                    // Suspend first so the system's zoom-out to the Home
                    // Screen plays; then actually terminate, so the next
                    // launch is a cold start (boot ident and all) instead of
                    // a warm resume. exit() alone looks like a crash — the
                    // app vanishes with no animation.
                    UIApplication.shared.perform(Selector(("suspend")))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        exit(0)
                    }
                }
                result(true)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
        self.systemChannel = systemChannel

        // Top Shelf is a separate, low-memory TVServices extension. Flutter
        // writes only a bounded JSON snapshot into the shared App Group; the
        // extension can then render while this app is not running. In the
        // opposite direction, a Top Shelf URL is reduced to metadata and
        // handed to Dart so the existing detail-page route remains the single
        // source of navigation truth.
        let topShelfChannel = FlutterMethodChannel(
            name: "debrify/topshelf",
            binaryMessenger: flutterViewController.binaryMessenger)
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.topShelfAppGroup) {
            let previewDirectory = container.appendingPathComponent(
                Self.topShelfPreviewDirectory,
                isDirectory: true)
            pruneTopShelfPreviews(in: previewDirectory, preserving: nil)
            NSLog("[TopShelf] App Group ready: %@", container.path)
        } else {
            NSLog("[TopShelf] App Group unavailable at launch")
        }
        topShelfChannel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(FlutterError(code: "unavailable", message: nil, details: nil))
                return
            }
            switch call.method {
            case "publish":
                guard let json = call.arguments as? String,
                      let data = json.data(using: .utf8),
                      data.count <= 512 * 1024 else {
                    result(FlutterError(
                        code: "invalid_snapshot",
                        message: "Top Shelf snapshot is missing or too large.",
                        details: nil))
                    return
                }
                do {
                    guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          [1, 2].contains(root["version"] as? Int ?? -1),
                          root["items"] is [[String: Any]] else {
                        result(FlutterError(
                            code: "invalid_snapshot",
                            message: "Top Shelf snapshot has an unsupported shape.",
                            details: nil))
                        return
                    }
                    guard let container = FileManager.default.containerURL(
                        forSecurityApplicationGroupIdentifier: Self.topShelfAppGroup) else {
                        NSLog("[TopShelf] Publish rejected: App Group unavailable")
                        result(FlutterError(
                            code: "app_group_unavailable",
                            message: "The Top Shelf App Group is unavailable.",
                            details: nil))
                        return
                    }
                    let destination = container.appendingPathComponent(Self.topShelfSnapshotPath)
                    if root["version"] as? Int == 2 {
                        guard let revision = root["snapshotRevision"] as? Int,
                              let owner = root["ownerProfileId"] as? String,
                              owner.range(of: #"^[A-Za-z0-9_-]{1,96}$"#, options: .regularExpression) != nil,
                              let actions = root.removeValue(forKey: "actions") as? [String: Any],
                              actions.count <= 100 else {
                            throw NSError(domain: "TopShelf", code: 10, userInfo: [NSLocalizedDescriptionKey: "Profile action map is invalid"])
                        }
                        let actionDocument: [String: Any] = [
                            "version": 1,
                            "snapshotRevision": revision,
                            "actions": actions,
                        ]
                        let actionData = try JSONSerialization.data(withJSONObject: actionDocument, options: [.sortedKeys])
                        let actionURL = container.appendingPathComponent(Self.topShelfActionsPath)
                        try actionData.write(to: actionURL, options: .atomic)
                    }
                    let snapshotData = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
                    // Snapshot is the commit marker: the extension exposes
                    // actions only when its revision matches the map written first.
                    try snapshotData.write(to: destination, options: .atomic)
                    let itemCount = (root["items"] as? [[String: Any]])?.count ?? 0
                    NSLog("[TopShelf] Published %ld item(s)", itemCount)
                    TVTopShelfContentProvider.topShelfContentDidChange()
                    result(nil)
                } catch {
                    NSLog("[TopShelf] Publish failed: %@", error.localizedDescription)
                    result(FlutterError(
                        code: "snapshot_write_failed",
                        message: error.localizedDescription,
                        details: nil))
                }
            case "clear":
                if let container = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: Self.topShelfAppGroup) {
                    try? FileManager.default.removeItem(at: container.appendingPathComponent(Self.topShelfSnapshotPath))
                    try? FileManager.default.removeItem(at: container.appendingPathComponent(Self.topShelfActionsPath))
                    pruneTopShelfPreviews(
                        in: container.appendingPathComponent(Self.topShelfPreviewDirectory, isDirectory: true),
                        preserving: nil)
                    TVTopShelfContentProvider.topShelfContentDidChange()
                }
                result(nil)
            case "cachePreview":
                guard let arguments = call.arguments as? [String: Any] else {
                    result(FlutterError(
                        code: "invalid_preview",
                        message: TopShelfPreviewError.invalidArguments.localizedDescription,
                        details: nil))
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self else {
                        result(FlutterError(code: "unavailable", message: nil, details: nil))
                        return
                    }
                    do {
                        let path = try await self.cacheTopShelfPreview(arguments)
                        result(path)
                    } catch {
                        NSLog("[TopShelf] Preview cache failed: %@", error.localizedDescription)
                        result(FlutterError(
                            code: "preview_cache_failed",
                            message: error.localizedDescription,
                            details: nil))
                    }
                }
            case "takePendingAction":
                NSLog("[TopShelf] Flutter channel connected")
                let action = self.pendingTopShelfAction
                self.pendingTopShelfAction = nil
                result(action)
            case "clearPendingAction":
                if let acknowledged = call.arguments as? [String: String],
                   self.pendingTopShelfAction == acknowledged {
                    self.pendingTopShelfAction = nil
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        self.topShelfChannel = topShelfChannel

        if let launchURL = launchOptions?[.url] as? URL,
           let action = topShelfAction(from: launchURL) {
            pendingTopShelfAction = action
        }

        // Apple TV's keyboard never tells Flutter the user finished.
        //
        // The engine raises a submit action from exactly one place — when the
        // platform inserts a literal "\n" (FlutterTextInputPlugin.mm,
        // -shouldChangeTextInRange:replacementText:). That is the iOS inline
        // keyboard's contract. tvOS presents a full-screen keyboard whose
        // action button commits and dismisses WITHOUT inserting anything, so
        // the trigger never fires and `onSubmitted` never runs: every text
        // field on the platform is a dead end.
        //
        // UIKit does post the fact, though — verified on an Apple TV 4K
        // (tvOS 26.6): pressing the action key emits exactly one
        // UITextFieldTextDidEndEditingNotification, and typing emits none.
        // Bridge it to Dart, which treats it as "editing finished".
        //
        // Caveat, measured rather than assumed: dismissing with the remote's
        // BACK button emits the SAME notification, so commit and cancel are
        // indistinguishable here. Dart side decides what that's worth.
        let keyboardChannel = FlutterMethodChannel(
            name: "debrify/tvkeyboard",
            binaryMessenger: flutterViewController.binaryMessenger)
        self.keyboardChannel = keyboardChannel
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UITextFieldTextDidEndEditingNotification"),
            object: nil,
            queue: .main
        ) { [weak keyboardChannel] _ in
            keyboardChannel?.invokeMethod("endEditing", arguments: nil)
        }


        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func applicationWillResignActive(_ application: UIApplication) {
        profilePrivacy.coverIfNeeded(window)
        super.applicationWillResignActive(application)
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        profilePrivacy.uncover()
        super.applicationDidBecomeActive(application)
    }

    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard let action = topShelfAction(from: url) else {
            return super.application(app, open: url, options: options)
        }
        pendingTopShelfAction = action
        topShelfChannel?.invokeMethod("action", arguments: action)
        return true
    }

    private func topShelfAction(from url: URL) -> [String: String]? {
        guard url.scheme?.lowercased() == "debrify",
              url.host?.lowercased() == "topshelf",
              url.path == "/display",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
            return consumeTopShelfToken(token)
        }
        var values: [String: String] = [:]
        let allowed = Set(["imdbId", "type", "title", "posterURL", "year"])
        for item in components.queryItems ?? [] where allowed.contains(item.name) {
            if let value = item.value, value.count <= 2_048 {
                values[item.name] = value
            }
        }
        guard let imdbID = values["imdbId"],
              imdbID.range(of: #"^tt\d{7,10}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return values
    }

    private func consumeTopShelfToken(_ token: String) -> [String: String]? {
        guard token.range(of: #"^[A-Za-z0-9_-]{32,128}$"#, options: .regularExpression) != nil,
              let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Self.topShelfAppGroup) else { return nil }
        let snapshotURL = container.appendingPathComponent(Self.topShelfSnapshotPath)
        let actionsURL = container.appendingPathComponent(Self.topShelfActionsPath)
        guard let snapshotData = try? Data(contentsOf: snapshotURL),
              let actionsData = try? Data(contentsOf: actionsURL),
              let snapshot = try? JSONSerialization.jsonObject(with: snapshotData) as? [String: Any],
              var document = try? JSONSerialization.jsonObject(with: actionsData) as? [String: Any],
              snapshot["version"] as? Int == 2,
              let revision = snapshot["snapshotRevision"] as? Int,
              document["snapshotRevision"] as? Int == revision,
              var actions = document["actions"] as? [String: Any],
              var record = actions[token] as? [String: Any],
              record["consumed"] as? Bool == false,
              let expiresAt = record["expiresAtMs"] as? Int64,
              expiresAt >= Int64(Date().timeIntervalSince1970 * 1000),
              let owner = record["ownerProfileId"] as? String,
              owner == snapshot["ownerProfileId"] as? String,
              let authorizationRevision = record["profileAuthorizationRevision"] as? Int,
              authorizationRevision == snapshot["profileAuthorizationRevision"] as? Int,
              let action = record["action"] as? [String: Any],
              let imdbID = action["imdbId"] as? String,
              imdbID.range(of: #"^tt\d{7,10}$"#, options: .regularExpression) != nil else {
            return nil
        }
        record["consumed"] = true
        actions[token] = record
        document["actions"] = actions
        guard let updated = try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]),
              (try? updated.write(to: actionsURL, options: .atomic)) != nil else { return nil }
        var result: [String: String] = [
            "ownerProfileId": owner,
            "profileAuthorizationRevision": String(authorizationRevision),
            "imdbId": imdbID,
        ]
        for key in ["type", "title", "posterURL", "year"] {
            if let value = action[key] as? String, value.count <= 2_048 { result[key] = value }
        }
        return result
    }

    /// Downloads and remuxes a bounded trailer clip while the full app is
    /// running. The Top Shelf extension never performs this work: it receives
    /// only the relative path of the finished MP4 in the shared App Group.
    @MainActor
    private func cacheTopShelfPreview(_ arguments: [String: Any]) async throws -> String {
        guard let cacheKey = arguments["cacheKey"] as? String,
              cacheKey.count <= 96,
              cacheKey.range(
                of: #"^[A-Za-z0-9._-]+$"#,
                options: .regularExpression) != nil,
              let videoString = arguments["videoURL"] as? String,
              let videoURL = validatedTopShelfMediaURL(videoString) else {
            throw TopShelfPreviewError.invalidArguments
        }
        let includeAudio = arguments["includeAudio"] as? Bool ?? true
        let audioURL = (arguments["audioURL"] as? String).flatMap(validatedTopShelfMediaURL)
        let requestedDuration = (arguments["maxDurationSeconds"] as? NSNumber)?.doubleValue ?? 90
        let maxDuration = min(max(requestedDuration, 15), 120)

        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.topShelfAppGroup) else {
            throw TopShelfPreviewError.appGroupUnavailable
        }
        let previewDirectory = container.appendingPathComponent(
            Self.topShelfPreviewDirectory,
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: previewDirectory,
            withIntermediateDirectories: true)
        let fileName = "\(cacheKey).mp4"
        let destination = previewDirectory.appendingPathComponent(fileName)
        let relativePath = "\(Self.topShelfPreviewDirectory)/\(fileName)"

        if isFreshTopShelfPreview(destination) {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: destination.path)
            pruneTopShelfPreviews(in: previewDirectory, preserving: destination)
            NSLog("[TopShelf] Reused cached preview")
            return relativePath
        }

        let videoAsset = AVURLAsset(url: videoURL)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw TopShelfPreviewError.noVideoTrack
        }
        let sourceDuration = try await videoAsset.load(.duration)
        guard sourceDuration.isValid,
              !sourceDuration.isIndefinite,
              sourceDuration.seconds.isFinite,
              sourceDuration.seconds > 1 else {
            throw TopShelfPreviewError.invalidDuration
        }
        let durationLimit = CMTime(seconds: maxDuration, preferredTimescale: 600)
        let clipDuration = CMTimeCompare(sourceDuration, durationLimit) > 0
            ? durationLimit
            : sourceDuration

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw TopShelfPreviewError.compositionFailed
        }
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: clipDuration),
            of: sourceVideoTrack,
            at: .zero)
        if let transform = try? await sourceVideoTrack.load(.preferredTransform) {
            compositionVideoTrack.preferredTransform = transform
        }

        if includeAudio {
            do {
                let sourceAudioAsset = audioURL.map(AVURLAsset.init(url:)) ?? videoAsset
                let audioTracks = try await sourceAudioAsset.loadTracks(withMediaType: .audio)
                if let sourceAudioTrack = audioTracks.first {
                    let audioDuration = try await sourceAudioAsset.load(.duration)
                    if audioDuration.isValid,
                       !audioDuration.isIndefinite,
                       audioDuration.seconds.isFinite,
                       audioDuration.seconds > 0,
                       let compositionAudioTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid) {
                        let usableAudioDuration = CMTimeCompare(audioDuration, clipDuration) < 0
                            ? audioDuration
                            : clipDuration
                        try compositionAudioTrack.insertTimeRange(
                            CMTimeRange(start: .zero, duration: usableAudioDuration),
                            of: sourceAudioTrack,
                            at: .zero)
                    }
                }
            } catch {
                // A restricted/missing audio rendition should degrade to a
                // silent preview, not discard a perfectly usable video track.
                NSLog("[TopShelf] Preview audio unavailable; caching video only")
            }
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough),
              exporter.supportedFileTypes.contains(.mp4) else {
            throw TopShelfPreviewError.exportUnavailable
        }
        let temporary = previewDirectory.appendingPathComponent(
            ".\(cacheKey)-\(UUID().uuidString).partial.mp4")
        try? FileManager.default.removeItem(at: temporary)
        exporter.outputURL = temporary
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        do {
            try await exportTopShelfPreview(exporter)
            let attributes = try FileManager.default.attributesOfItem(atPath: temporary.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard size >= 256 * 1024 else {
                throw TopShelfPreviewError.outputInvalid
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(
                    destination,
                    withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            pruneTopShelfPreviews(in: previewDirectory, preserving: destination)
            NSLog("[TopShelf] Cached preview (%ld bytes)", size)
            return relativePath
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func validatedTopShelfMediaURL(_ raw: String) -> URL? {
        guard raw.count <= 16_384,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private func isFreshTopShelfPreview(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value >= 256 * 1024,
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < Self.topShelfPreviewMaxAge else {
            return false
        }
        return true
    }

    private func exportTopShelfPreview(_ exporter: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exporter.error ?? TopShelfPreviewError.exportFailed)
                default:
                    continuation.resume(throwing: TopShelfPreviewError.exportFailed)
                }
            }
        }
    }

    private func pruneTopShelfPreviews(in directory: URL, preserving: URL?) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: []) else {
            return
        }
        let now = Date()
        var candidates: [(url: URL, modified: Date, size: Int64)] = []
        for file in files where file.pathExtension.lowercased() == "mp4" {
            guard let values = try? file.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                continue
            }
            let modified = values.contentModificationDate ?? .distantPast
            if file.lastPathComponent.hasPrefix(".") {
                if now.timeIntervalSince(modified) >= 60 * 60 {
                    try? manager.removeItem(at: file)
                }
                continue
            }
            let mustPreserve = preserving == file
            if !mustPreserve && now.timeIntervalSince(modified) >= Self.topShelfPreviewMaxAge {
                try? manager.removeItem(at: file)
                continue
            }
            candidates.append((file, modified, Int64(values.fileSize ?? 0)))
        }
        candidates.sort { $0.modified > $1.modified }
        var keptCount = 0
        var keptBytes: Int64 = 0
        for candidate in candidates {
            let canKeep = candidate.url == preserving ||
                (keptCount < Self.topShelfPreviewMaxFiles &&
                 keptBytes + candidate.size <= Self.topShelfPreviewMaxBytes)
            if canKeep {
                keptCount += 1
                keptBytes += candidate.size
            } else {
                try? manager.removeItem(at: candidate.url)
            }
        }
    }
}
