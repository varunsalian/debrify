import 'package:debrify/services/profiles/profile_preferences.dart';

final class ExternalPlayerStorage {
  const ExternalPlayerStorage._();

  // External Player settings
  // Default player mode: 'debrify' (app player), 'external' (external player), 'deovr' (DeoVR on Android)
  static const String _defaultPlayerModeKey = 'default_player_mode';
  static const String _externalPlayerPreferredKey = 'external_player_preferred';
  static const String _externalPlayerCustomPathKey = 'external_player_custom_path';
  static const String _externalPlayerCustomNameKey = 'external_player_custom_name';
  static const String _externalPlayerCustomCommandKey = 'external_player_custom_command';
  // iOS External Player settings
  static const String _iosExternalPlayerPreferredKey = 'ios_external_player_preferred';
  static const String _iosCustomSchemeTemplateKey = 'ios_custom_scheme_template';
  // Linux External Player settings
  static const String _linuxExternalPlayerPreferredKey = 'linux_external_player_preferred';
  static const String _linuxCustomCommandKey = 'linux_custom_command';
  // Windows External Player settings
  static const String _windowsExternalPlayerPreferredKey = 'windows_external_player_preferred';
  static const String _windowsCustomCommandKey = 'windows_custom_command';

  // External Player Settings methods

  /// Get default player mode
  /// Returns 'debrify' (built-in player) by default
  /// Valid values: 'debrify', 'external', 'deovr'
  static Future<String> getDefaultPlayerMode() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_defaultPlayerModeKey) ?? 'debrify';
  }

  /// Set default player mode
  /// Valid values: 'debrify', 'external', 'deovr'
  static Future<void> setDefaultPlayerMode(String mode) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultPlayerModeKey, mode);
  }

  /// Get preferred external player key
  /// Returns 'system_default' if not set
  static Future<String> getPreferredExternalPlayer() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_externalPlayerPreferredKey) ?? 'system_default';
  }

  /// Set preferred external player key
  static Future<void> setPreferredExternalPlayer(String playerKey) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_externalPlayerPreferredKey, playerKey);
  }

  /// Get custom external player path (for custom player option)
  static Future<String?> getCustomExternalPlayerPath() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_externalPlayerCustomPathKey);
  }

  /// Set custom external player path
  static Future<void> setCustomExternalPlayerPath(String? path) async {
    final prefs = await ProfilePreferences.instance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_externalPlayerCustomPathKey);
    } else {
      await prefs.setString(_externalPlayerCustomPathKey, path);
    }
  }

  /// Get custom external player display name
  static Future<String?> getCustomExternalPlayerName() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_externalPlayerCustomNameKey);
  }

  /// Set custom external player display name
  static Future<void> setCustomExternalPlayerName(String? name) async {
    final prefs = await ProfilePreferences.instance();
    if (name == null || name.isEmpty) {
      await prefs.remove(_externalPlayerCustomNameKey);
    } else {
      await prefs.setString(_externalPlayerCustomNameKey, name);
    }
  }

  /// Get custom external player command template
  /// Should contain {url} placeholder, optionally {title}
  static Future<String?> getCustomExternalPlayerCommand() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_externalPlayerCustomCommandKey);
  }

  /// Set custom external player command template
  static Future<void> setCustomExternalPlayerCommand(String? command) async {
    final prefs = await ProfilePreferences.instance();
    if (command == null || command.isEmpty) {
      await prefs.remove(_externalPlayerCustomCommandKey);
    } else {
      await prefs.setString(_externalPlayerCustomCommandKey, command);
    }
  }

  // ============================================================
  // iOS External Player Settings
  // ============================================================

  /// Get preferred iOS external player key
  static Future<String> getPreferredIOSExternalPlayer() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_iosExternalPlayerPreferredKey) ?? 'vlc';
  }

  /// Set preferred iOS external player key
  static Future<void> setPreferredIOSExternalPlayer(String playerKey) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_iosExternalPlayerPreferredKey, playerKey);
  }

  /// Get iOS custom URL scheme template
  /// Should contain {url} placeholder, e.g., "myplayer://play?url={url}"
  static Future<String?> getIOSCustomSchemeTemplate() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_iosCustomSchemeTemplateKey);
  }

  /// Set iOS custom URL scheme template
  static Future<void> setIOSCustomSchemeTemplate(String? template) async {
    final prefs = await ProfilePreferences.instance();
    if (template == null || template.isEmpty) {
      await prefs.remove(_iosCustomSchemeTemplateKey);
    } else {
      await prefs.setString(_iosCustomSchemeTemplateKey, template);
    }
  }

  // ============================================================
  // Linux External Player Settings
  // ============================================================

  /// Get preferred Linux external player key
  static Future<String> getPreferredLinuxExternalPlayer() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_linuxExternalPlayerPreferredKey) ?? 'system_default';
  }

  /// Set preferred Linux external player key
  static Future<void> setPreferredLinuxExternalPlayer(String playerKey) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_linuxExternalPlayerPreferredKey, playerKey);
  }

  /// Get Linux custom command template
  /// Should contain {url} placeholder, e.g., "vlc --fullscreen {url}"
  static Future<String?> getLinuxCustomCommand() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_linuxCustomCommandKey);
  }

  /// Set Linux custom command template
  static Future<void> setLinuxCustomCommand(String? command) async {
    final prefs = await ProfilePreferences.instance();
    if (command == null || command.isEmpty) {
      await prefs.remove(_linuxCustomCommandKey);
    } else {
      await prefs.setString(_linuxCustomCommandKey, command);
    }
  }

  // ============================================================
  // Windows External Player Settings
  // ============================================================

  /// Get preferred Windows external player key
  static Future<String> getPreferredWindowsExternalPlayer() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_windowsExternalPlayerPreferredKey) ?? 'system_default';
  }

  /// Set preferred Windows external player key
  static Future<void> setPreferredWindowsExternalPlayer(
    String playerKey,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_windowsExternalPlayerPreferredKey, playerKey);
  }

  /// Get Windows custom command template
  /// Should contain {url} placeholder, e.g., "vlc --fullscreen {url}"
  static Future<String?> getWindowsCustomCommand() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_windowsCustomCommandKey);
  }

  /// Set Windows custom command template
  static Future<void> setWindowsCustomCommand(String? command) async {
    final prefs = await ProfilePreferences.instance();
    if (command == null || command.isEmpty) {
      await prefs.remove(_windowsCustomCommandKey);
    } else {
      await prefs.setString(_windowsCustomCommandKey, command);
    }
  }

  /// Clear all external player settings
  static Future<void> clearExternalPlayerSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_defaultPlayerModeKey);
    await prefs.remove(_externalPlayerPreferredKey);
    await prefs.remove(_externalPlayerCustomPathKey);
    await prefs.remove(_externalPlayerCustomNameKey);
    await prefs.remove(_externalPlayerCustomCommandKey);
  }
}
