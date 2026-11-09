import Cocoa
import FlutterMacOS
import CryptoKit

private final class MacOsDeviceSecretCipher {
  private let store = MacOsDeviceKeyStore(
    directory: MacOsDeviceKeyStore.defaultDirectory(),
    legacy: KeychainLegacyDeviceKeySource()
  )

  func install(on messenger: FlutterBinaryMessenger) -> FlutterMethodChannel {
    let channel = FlutterMethodChannel(name: "debrify/device_secret", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterError(code: "unavailable", message: nil, details: nil)); return }
      do {
        switch call.method {
        case "initialize":
          let args = call.arguments as? [String: Any]
          let allowCreate = args?["allowCreate"] as? Bool ?? true
          _ = try self.key(allowCreate: allowCreate)
          result(self.store.keyCopyDeferred ? "key_copy_deferred" : true)
        case "seal":
          let (input, aad) = try self.arguments(call)
          let box = try AES.GCM.seal(input, using: try self.key(allowCreate: false), authenticating: aad)
          guard let combined = box.combined else { throw NSError(domain: "DeviceSecret", code: 2) }
          result(combined.base64EncodedString())
        case "open":
          let (input, aad) = try self.arguments(call, payloadName: "envelope")
          let box = try AES.GCM.SealedBox(combined: input)
          result(try AES.GCM.open(box, using: try self.key(allowCreate: false), authenticating: aad).base64EncodedString())
        case "destroy": try self.store.destroy(); result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      } catch DeviceSecretError.missing {
        result(FlutterError(code: "device_secret_missing", message: nil, details: nil))
      } catch DeviceSecretError.unreadable {
        result(FlutterError(code: "device_secret_unreadable", message: nil, details: nil))
      } catch DeviceSecretError.keychainDenied {
        result(FlutterError(code: "device_secret_keychain_denied", message: nil, details: nil))
      } catch CryptoKitError.authenticationFailure {
        result(FlutterError(code: "device_secret_record_unreadable", message: nil, details: nil))
      } catch {
        result(FlutterError(code: "device_secret_failed", message: error.localizedDescription, details: nil))
      }
    }
    return channel
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

  private func key(allowCreate: Bool) throws -> SymmetricKey {
    SymmetricKey(data: try store.key(allowCreate: allowCreate))
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
