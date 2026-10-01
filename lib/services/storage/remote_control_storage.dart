import 'dart:convert';
import 'package:debrify/services/profiles/profile_preferences.dart';

final class RemoteControlStorage {
  const RemoteControlStorage._();

  // Remote Control Settings
  static const String _remoteControlEnabledKey = 'remote_control_enabled';
  static const String _remoteIntroShownKey = 'remote_intro_shown';
  static const String _remoteTvDeviceNameKey = 'remote_tv_device_name';
  static const String _remoteLastDeviceKey = 'remote_last_device';

  // ============================================================================
  // Remote Control Settings
  // ============================================================================

  /// Get whether remote control feature is enabled
  static Future<bool> getRemoteControlEnabled() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getBool(_remoteControlEnabledKey) ?? true;
  }

  /// Set whether remote control feature is enabled
  static Future<void> setRemoteControlEnabled(bool enabled) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setBool(_remoteControlEnabledKey, enabled);
  }

  /// Get whether remote intro dialog has been shown
  static Future<bool> getRemoteIntroShown() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getBool(_remoteIntroShownKey) ?? false;
  }

  /// Set whether remote intro dialog has been shown
  static Future<void> setRemoteIntroShown(bool shown) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setBool(_remoteIntroShownKey, shown);
  }

  /// Get TV device name for remote control (TV only)
  static Future<String?> getRemoteTvDeviceName() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getString(_remoteTvDeviceNameKey);
  }

  /// Set TV device name for remote control (TV only)
  static Future<void> setRemoteTvDeviceName(String name) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setString(_remoteTvDeviceNameKey, name);
  }

  /// Get last connected device info (Mobile only)
  static Future<Map<String, dynamic>?> getRemoteLastDevice() async {
    final prefs = await DevicePreferences.instance();
    final raw = prefs.getString(_remoteLastDeviceKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Save last connected device info (Mobile only)
  static Future<void> setRemoteLastDevice(Map<String, dynamic> device) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setString(_remoteLastDeviceKey, jsonEncode(device));
  }

  /// Clear last connected device info
  static Future<void> clearRemoteLastDevice() async {
    final prefs = await DevicePreferences.instance();
    await prefs.remove(_remoteLastDeviceKey);
  }
}
