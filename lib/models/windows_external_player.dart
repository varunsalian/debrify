import 'package:flutter/material.dart';

/// Supported external video players for Windows
/// Each player is launched via command line
enum WindowsExternalPlayer {
  systemDefault,
  vlc,
  mpv,
  mpcHc,
  potPlayer,
  customCommand,
}

extension WindowsExternalPlayerExtension on WindowsExternalPlayer {
  /// Human-readable display name
  String get displayName {
    switch (this) {
      case WindowsExternalPlayer.systemDefault:
        return 'System Default';
      case WindowsExternalPlayer.vlc:
        return 'VLC';
      case WindowsExternalPlayer.mpv:
        return 'mpv';
      case WindowsExternalPlayer.mpcHc:
        return 'MPC-HC';
      case WindowsExternalPlayer.potPlayer:
        return 'PotPlayer';
      case WindowsExternalPlayer.customCommand:
        return 'Custom Command';
    }
  }

  /// Description of the player
  String get description {
    switch (this) {
      case WindowsExternalPlayer.systemDefault:
        return 'Opens with default video player';
      case WindowsExternalPlayer.vlc:
        return 'Popular cross-platform media player';
      case WindowsExternalPlayer.mpv:
        return 'Lightweight, powerful media player';
      case WindowsExternalPlayer.mpcHc:
        return 'Media Player Classic - Home Cinema';
      case WindowsExternalPlayer.potPlayer:
        return 'Feature-rich multimedia player';
      case WindowsExternalPlayer.customCommand:
        return 'Define your own command';
    }
  }

  /// Command/executable name for the player
  /// Note: For MPC-HC and PotPlayer, these may need full paths if not in PATH
  String get executable {
    switch (this) {
      case WindowsExternalPlayer.systemDefault:
        return 'explorer.exe'; // Opens URLs with default handler
      case WindowsExternalPlayer.vlc:
        return 'vlc';
      case WindowsExternalPlayer.mpv:
        return 'mpv';
      case WindowsExternalPlayer.mpcHc:
        return 'mpc-hc64'; // or mpc-hc for 32-bit
      case WindowsExternalPlayer.potPlayer:
        return 'PotPlayerMini64'; // or PotPlayerMini for 32-bit
      case WindowsExternalPlayer.customCommand:
        return ''; // User-defined
    }
  }

  /// Common installation paths for players not typically in PATH
  /// Returns list of paths to check (64-bit first, then 32-bit)
  List<String> get commonPaths {
    switch (this) {
      case WindowsExternalPlayer.mpcHc:
        return [
          r'C:\Program Files\MPC-HC\mpc-hc64.exe',
          r'C:\Program Files (x86)\MPC-HC\mpc-hc.exe',
          r'C:\Program Files\MPC-HC64\mpc-hc64.exe',
        ];
      case WindowsExternalPlayer.potPlayer:
        return [
          r'C:\Program Files\DAUM\PotPlayer\PotPlayerMini64.exe',
          r'C:\Program Files (x86)\DAUM\PotPlayer\PotPlayerMini.exe',
          r'C:\Program Files\PotPlayer\PotPlayerMini64.exe',
          r'C:\Program Files (x86)\PotPlayer\PotPlayerMini.exe',
        ];
      case WindowsExternalPlayer.vlc:
        return [
          r'C:\Program Files\VideoLAN\VLC\vlc.exe',
          r'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe',
        ];
      case WindowsExternalPlayer.mpv:
        return [
          r'C:\Program Files\mpv\mpv.exe',
          r'C:\Program Files (x86)\mpv\mpv.exe',
          // Scoop installation path
          r'C:\Users\${USER}\scoop\apps\mpv\current\mpv.exe',
        ];
      default:
        return [];
    }
  }

  /// Build command arguments for launching the player
  /// Returns a list where first element is executable, rest are arguments
  List<String> buildCommand(String videoUrl, {String? title, String? resolvedPath}) {
    // Use resolved path if provided (for players found via commonPaths)
    final exec = resolvedPath ?? executable;

    switch (this) {
      case WindowsExternalPlayer.systemDefault:
        // explorer.exe opens URL with system default handler
        return ['explorer.exe', videoUrl];

      case WindowsExternalPlayer.vlc:
        // VLC: --play-and-exit quits after playback
        // --no-video-title-show hides the URL from being shown
        return [
          exec,
          '--play-and-exit',
          '--no-video-title-show',
          if (title != null && title.isNotEmpty) ...['--meta-title', title],
          videoUrl,
        ];

      case WindowsExternalPlayer.mpv:
        // mpv: --title sets window title
        return [
          exec,
          if (title != null && title.isNotEmpty) '--title=$title',
          videoUrl,
        ];

      case WindowsExternalPlayer.mpcHc:
        // MPC-HC: /play starts playback, /close exits after playback
        // Note: MPC-HC uses forward slashes for arguments
        return [
          exec,
          videoUrl,
          '/play',
          '/close',
        ];

      case WindowsExternalPlayer.potPlayer:
        // PotPlayer: URL as argument
        // Limited command-line options available
        return [
          exec,
          videoUrl,
        ];

      case WindowsExternalPlayer.customCommand:
        // Custom command - should not be called directly
        // Use buildWindowsCustomCommand instead
        return [videoUrl];
    }
  }

  /// Icon representing the player
  IconData get icon {
    switch (this) {
      case WindowsExternalPlayer.systemDefault:
        return Icons.open_in_new_rounded;
      case WindowsExternalPlayer.vlc:
        return Icons.play_circle_filled_rounded;
      case WindowsExternalPlayer.mpv:
        return Icons.smart_display_rounded;
      case WindowsExternalPlayer.mpcHc:
        return Icons.movie_rounded;
      case WindowsExternalPlayer.potPlayer:
        return Icons.ondemand_video_rounded;
      case WindowsExternalPlayer.customCommand:
        return Icons.terminal_rounded;
    }
  }

  /// Storage key value for persistence
  String get storageKey {
    switch (this) {
      case WindowsExternalPlayer.systemDefault:
        return 'system_default';
      case WindowsExternalPlayer.vlc:
        return 'vlc';
      case WindowsExternalPlayer.mpv:
        return 'mpv';
      case WindowsExternalPlayer.mpcHc:
        return 'mpc_hc';
      case WindowsExternalPlayer.potPlayer:
        return 'potplayer';
      case WindowsExternalPlayer.customCommand:
        return 'custom_command';
    }
  }

  /// Create WindowsExternalPlayer from storage key
  static WindowsExternalPlayer fromStorageKey(String key) {
    switch (key) {
      case 'system_default':
        return WindowsExternalPlayer.systemDefault;
      case 'vlc':
        return WindowsExternalPlayer.vlc;
      case 'mpv':
        return WindowsExternalPlayer.mpv;
      case 'mpc_hc':
        return WindowsExternalPlayer.mpcHc;
      case 'potplayer':
        return WindowsExternalPlayer.potPlayer;
      case 'custom_command':
        return WindowsExternalPlayer.customCommand;
      default:
        return WindowsExternalPlayer.systemDefault;
    }
  }
}

/// Placeholder for video URL in custom command
const String windowsUrlPlaceholder = '{url}';

/// Placeholder for video title in custom command
const String windowsTitlePlaceholder = '{title}';

/// Build a custom command from a template
/// Template should contain {url} placeholder
/// Example: "vlc --fullscreen {url}"
List<String> buildWindowsCustomCommand(String template, String videoUrl,
    {String? title}) {
  if (template.trim().isEmpty) {
    return [];
  }

  // Replace placeholders
  String command = template
      .replaceAll(windowsUrlPlaceholder, videoUrl)
      .replaceAll(windowsTitlePlaceholder, title ?? '');

  // Parse the command into parts (handle quoted strings)
  return _parseWindowsCommand(command);
}

/// Parse a command string into executable and arguments
/// Handles quoted strings properly
List<String> _parseWindowsCommand(String command) {
  final List<String> parts = [];
  final StringBuffer current = StringBuffer();
  bool inQuotes = false;
  String? quoteChar;

  for (int i = 0; i < command.length; i++) {
    final char = command[i];

    if ((char == '"' || char == "'") && !inQuotes) {
      inQuotes = true;
      quoteChar = char;
    } else if (char == quoteChar && inQuotes) {
      inQuotes = false;
      quoteChar = null;
    } else if (char == ' ' && !inQuotes) {
      if (current.isNotEmpty) {
        parts.add(current.toString());
        current.clear();
      }
    } else {
      current.write(char);
    }
  }

  if (current.isNotEmpty) {
    parts.add(current.toString());
  }

  return parts;
}

/// Validate a custom command template
class WindowsCustomCommandValidation {
  final bool isValid;
  final String? errorMessage;

  const WindowsCustomCommandValidation({
    required this.isValid,
    this.errorMessage,
  });

  factory WindowsCustomCommandValidation.valid() {
    return const WindowsCustomCommandValidation(isValid: true);
  }

  factory WindowsCustomCommandValidation.invalid(String message) {
    return WindowsCustomCommandValidation(isValid: false, errorMessage: message);
  }
}

WindowsCustomCommandValidation validateWindowsCustomCommand(String? command) {
  if (command == null || command.trim().isEmpty) {
    return WindowsCustomCommandValidation.invalid('Command cannot be empty');
  }

  final trimmed = command.trim();

  if (!trimmed.contains(windowsUrlPlaceholder)) {
    return WindowsCustomCommandValidation.invalid(
        'Command must contain $windowsUrlPlaceholder placeholder');
  }

  // Check for obviously invalid commands
  if (trimmed.startsWith(windowsUrlPlaceholder)) {
    return WindowsCustomCommandValidation.invalid(
        'Command must start with an executable');
  }

  return WindowsCustomCommandValidation.valid();
}
