import Flutter
import UserNotifications

/// Kick-off reminders as local notifications.
///
/// Dart always sends the complete set (`replaceAll`). The identifiers this
/// bridge scheduled last time are kept in UserDefaults; those missing from
/// the new set are removed, so a deleted or other-profile game never fires.
/// The rest are re-added, which replaces a pending request with the same
/// identifier, so a moved kick-off moves its alert without any ordering
/// assumption between removal and addition.
final class SportsReminderBridge {
  static let identifierPrefix = "sports-reminder:"
  private static let scheduledKey = "debrify.sportsReminders.scheduled"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.debrify.app/sports_reminders", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "requestPermission":
        self.requestPermission(result)
      case "replaceAll":
        let args = call.arguments as? [String: Any]
        self.replaceAll(args?["alerts"] as? [[String: Any]] ?? [])
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestPermission(_ result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
      granted, _ in
      DispatchQueue.main.async { result(granted) }
    }
  }

  private func replaceAll(_ alerts: [[String: Any]]) {
    let center = UNUserNotificationCenter.current()
    let defaults = UserDefaults.standard
    let previous = Set(defaults.stringArray(forKey: Self.scheduledKey) ?? [])
    var scheduled: [String] = []
    let now = Date()
    for alert in alerts {
      guard let id = alert["id"] as? String,
        let fireAtMs = (alert["fireAtMs"] as? NSNumber)?.doubleValue
      else { continue }
      // An interval, not a calendar date: a time-zone change while it is
      // pending must not move an absolute kick-off.
      let interval = Date(timeIntervalSince1970: fireAtMs / 1000).timeIntervalSince(now)
      guard interval > 1 else { continue }
      let content = UNMutableNotificationContent()
      content.title = alert["title"] as? String ?? ""
      content.body = alert["body"] as? String ?? ""
      content.sound = .default
      let identifier = Self.identifierPrefix + id
      center.add(
        UNNotificationRequest(
          identifier: identifier,
          content: content,
          trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
      scheduled.append(identifier)
    }
    let dropped = previous.subtracting(scheduled)
    if !dropped.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: Array(dropped))
    }
    defaults.set(scheduled, forKey: Self.scheduledKey)
  }
}
