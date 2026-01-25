import 'package:flutter/material.dart';

/// Supported external video players for macOS
enum ExternalPlayer {
  systemDefault,
  vlc,
  iina,
  mpv,
  quickTime,
  infuse,
  customApp,
  customCommand,
}

extension ExternalPlayerExtension on ExternalPlayer {
  /// Human-readable display name
  String get displayName {
    switch (this) {
      case ExternalPlayer.systemDefault:
        return 'System Default';
      case ExternalPlayer.vlc:
        return 'VLC';
      case ExternalPlayer.iina:
        return 'IINA';
      case ExternalPlayer.mpv:
        return 'mpv';
      case ExternalPlayer.quickTime:
        return 'QuickTime Player';
      case ExternalPlayer.infuse:
        return 'Infuse';
      case ExternalPlayer.customApp:
        return 'Custom App';
      case ExternalPlayer.customCommand:
        return 'Custom Command';
    }
  }

  /// macOS application bundle name (for `open -a`)
  /// Returns null for CLI tools or system default
  String? get macOSAppName {
    switch (this) {
      case ExternalPlayer.systemDefault:
        return null;
      case ExternalPlayer.vlc:
        return 'VLC';
      case ExternalPlayer.iina:
        return 'IINA';
      case ExternalPlayer.mpv:
        return null; // CLI tool
      case ExternalPlayer.quickTime:
        return 'QuickTime Player';
      case ExternalPlayer.infuse:
        return 'Infuse';
      case ExternalPlayer.customApp:
        return null; // Uses custom path
      case ExternalPlayer.customCommand:
        return null; // Uses custom command
    }
  }

  /// Command-line executable name (for CLI tools like mpv)
  /// Returns null for .app bundles
  String? get macOSCommand {
    switch (this) {
      case ExternalPlayer.mpv:
        return 'mpv';
      default:
        return null;
    }
  }

  /// Icon representing the player
  IconData get icon {
    switch (this) {
      case ExternalPlayer.systemDefault:
        return Icons.open_in_new_rounded;
      case ExternalPlayer.vlc:
        return Icons.play_circle_filled_rounded;
      case ExternalPlayer.iina:
        return Icons.play_arrow_rounded;
      case ExternalPlayer.mpv:
        return Icons.terminal_rounded;
      case ExternalPlayer.quickTime:
        return Icons.movie_rounded;
      case ExternalPlayer.infuse:
        return Icons.smart_display_rounded;
      case ExternalPlayer.customApp:
        return Icons.folder_open_rounded;
      case ExternalPlayer.customCommand:
        return Icons.code_rounded;
    }
  }

  /// Storage key value for persistence
  String get storageKey {
    switch (this) {
      case ExternalPlayer.systemDefault:
        return 'system_default';
      case ExternalPlayer.vlc:
        return 'vlc';
      case ExternalPlayer.iina:
        return 'iina';
      case ExternalPlayer.mpv:
        return 'mpv';
      case ExternalPlayer.quickTime:
        return 'quicktime';
      case ExternalPlayer.infuse:
        return 'infuse';
      case ExternalPlayer.customApp:
        return 'custom_app';
      case ExternalPlayer.customCommand:
        return 'custom_command';
    }
  }

  /// Create ExternalPlayer from storage key
  static ExternalPlayer fromStorageKey(String key) {
    switch (key) {
      case 'vlc':
        return ExternalPlayer.vlc;
      case 'iina':
        return ExternalPlayer.iina;
      case 'mpv':
        return ExternalPlayer.mpv;
      case 'quicktime':
        return ExternalPlayer.quickTime;
      case 'infuse':
        return ExternalPlayer.infuse;
      case 'custom':
        // Legacy key - map to customApp for backwards compatibility
        return ExternalPlayer.customApp;
      case 'custom_app':
        return ExternalPlayer.customApp;
      case 'custom_command':
        return ExternalPlayer.customCommand;
      case 'system_default':
      default:
        return ExternalPlayer.systemDefault;
    }
  }
}
