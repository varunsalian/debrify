import Cocoa
import FlutterMacOS
import CryptoKit
import Security

private final class MacOsDeviceSecretCipher {
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
      kSecValueData as String: bytes,
    ]
    let addStatus = SecItemAdd(add as CFDictionary, nil)
    guard addStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus)) }
    return SymmetricKey(data: bytes)
  }
}

class MainFlutterWindow: NSWindow {
  private var deviceSecretChannel: FlutterMethodChannel?
  private var profilePrivacyChannel: FlutterMethodChannel?
  private let deviceSecretCipher = MacOsDeviceSecretCipher()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    deviceSecretChannel = deviceSecretCipher.install(on: flutterViewController.engine.binaryMessenger)
    profilePrivacyChannel = FlutterMethodChannel(
      name: "com.debrify.app/profile_privacy",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    profilePrivacyChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setSensitive",
            let args = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      let sensitive = args["sensitive"] as? Bool ?? false
      self?.sharingType = sensitive ? .none : .readOnly
      result(true)
    }

    excludeDeviceBoundStateFromBackup()

    super.awakeFromNib()
  }

  private func excludeDeviceBoundStateFromBackup() {
    let manager = FileManager.default
    let roots = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    for root in roots {
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var mutable = root
      try? mutable.setResourceValues(values)
    }
  }
}
