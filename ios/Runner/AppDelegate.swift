import Flutter
import UIKit
import CryptoKit
import Security

private final class DeviceSecretCipher {
  private let service = "com.debrify.app.profile-device-secret"
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
          let payload = args[payloadName] as? String,
          let input = Data(base64Encoded: payload),
          let aadText = args["associatedData"] as? String,
          let aad = Data(base64Encoded: aadText) else {
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

private final class ProfilePrivacyController {
  var sensitive = false
  private var cover: UIView?

  func install(on messenger: FlutterBinaryMessenger) -> FlutterMethodChannel {
    let channel = FlutterMethodChannel(name: "com.debrify.app/profile_privacy", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setSensitive",
            let args = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented); return
      }
      self?.sensitive = args["sensitive"] as? Bool ?? false
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

  func uncover() { cover?.removeFromSuperview(); cover = nil }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let deviceSecretCipher = DeviceSecretCipher()
  private let profilePrivacy = ProfilePrivacyController()
  private var deviceSecretChannel: FlutterMethodChannel?
  private var profilePrivacyChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    _ = excludeDeviceBoundStateFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @discardableResult
  private func excludeDeviceBoundStateFromBackup() -> Bool {
    let manager = FileManager.default
    var urls: [URL] = []
    if let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      try? manager.createDirectory(at: support, withIntermediateDirectories: true)
      urls.append(support)
    }
    if let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first {
      let profiles = documents.appendingPathComponent("profiles", isDirectory: true)
      try? manager.createDirectory(at: profiles, withIntermediateDirectories: true)
      urls.append(profiles)
    }
    if let library = manager.urls(for: .libraryDirectory, in: .userDomainMask).first {
      // Mark the container, not only today's plist. SharedPreferences can
      // create/replace its plist after didFinishLaunching; directory-level
      // exclusion covers that first write and future atomic replacements.
      let preferences = library.appendingPathComponent("Preferences", isDirectory: true)
      try? manager.createDirectory(at: preferences, withIntermediateDirectories: true)
      urls.append(preferences)
    }
    var allExcluded = true
    for url in urls {
      guard manager.fileExists(atPath: url.path) else {
        allExcluded = false
        continue
      }
      do {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
        let verified = try mutable.resourceValues(forKeys: [.isExcludedFromBackupKey])
        allExcluded = allExcluded && verified.isExcludedFromBackup == true
      } catch {
        allExcluded = false
      }
    }
    return allExcluded
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DebrifyDeviceSecret") {
      deviceSecretChannel = deviceSecretCipher.install(on: registrar.messenger())
      profilePrivacyChannel = profilePrivacy.install(on: registrar.messenger())
    }
  }


  override func applicationWillResignActive(_ application: UIApplication) {
    profilePrivacy.coverIfNeeded(window)
    super.applicationWillResignActive(application)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    // Re-assert after Flutter/plugins have created their containers. This is
    // idempotent and closes the clean-install timing window.
    _ = excludeDeviceBoundStateFromBackup()
    profilePrivacy.uncover()
    super.applicationDidBecomeActive(application)
  }
}
