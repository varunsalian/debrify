import 'package:flutter/material.dart';

/// Supported external video players for Linux
/// Each player is launched via command line
enum LinuxExternalPlayer {
  systemDefault,
  vlc,
  mpv,
  celluloid,
  smplayer,
  customCommand,
}

extension LinuxExternalPlayerExtension on LinuxExternalPlayer {
  /// Human-readable display name
  String get displayName {
    switch (this) {
      case LinuxExternalPlayer.systemDefault:
        return 'System Default';
      case LinuxExternalPlayer.vlc:
        return 'VLC';
      case LinuxExternalPlayer.mpv:
        return 'mpv';
      case LinuxExternalPlayer.celluloid:
        return 'Celluloid';
      case LinuxExternalPlayer.smplayer:
        return 'SMPlayer';
      case LinuxExternalPlayer.customCommand:
        return 'Custom Command';
    }
  }

  /// Description of the player
  String get description {
    switch (this) {
      case LinuxExternalPlayer.systemDefault:
        return 'Opens with xdg-open';
      case LinuxExternalPlayer.vlc:
        return 'Popular cross-platform media player';
      case LinuxExternalPlayer.mpv:
        return 'Lightweight, powerful media player';
      case LinuxExternalPlayer.celluloid:
        return 'GTK+ frontend for mpv';
      case LinuxExternalPlayer.smplayer:
        return 'Qt frontend for mpv/mplayer';
      case LinuxExternalPlayer.customCommand:
        return 'Define your own command';
    }
  }

  /// Command/executable name for the player
  String get executable {
    switch (this) {
      case LinuxExternalPlayer.systemDefault:
        return 'xdg-open';
      case LinuxExternalPlayer.vlc:
        return 'vlc';
      case LinuxExternalPlayer.mpv:
        return 'mpv';
      case LinuxExternalPlayer.celluloid:
        return 'celluloid';
      case LinuxExternalPlayer.smplayer:
        return 'smplayer';
      case LinuxExternalPlayer.customCommand:
        return ''; // User-defined
    }
  }

  /// Build command arguments for launching the player
  /// Returns a list where first element is executable, rest are arguments
  List<String> buildCommand(String videoUrl, {String? title}) {
    switch (this) {
      case LinuxExternalPlayer.systemDefault:
        // xdg-open opens URL with system default handler
        return ['xdg-open', videoUrl];

      case LinuxExternalPlayer.vlc:
        // VLC: --play-and-exit quits after playback
        // --no-video-title-show hides the URL from being shown
        return [
          'vlc',
          '--play-and-exit',
          '--no-video-title-show',
          if (title != null && title.isNotEmpty) ...[
            '--meta-title',
            title,
          ],
          videoUrl,
        ];

      case LinuxExternalPlayer.mpv:
        // mpv: --title sets window title
        return [
          'mpv',
          if (title != null && title.isNotEmpty) '--title=$title',
          videoUrl,
        ];

      case LinuxExternalPlayer.celluloid:
        // Celluloid (formerly GNOME MPV)
        return ['celluloid', videoUrl];

      case LinuxExternalPlayer.smplayer:
        // SMPlayer
        return ['smplayer', videoUrl];

      case LinuxExternalPlayer.customCommand:
        // Custom command - should not be called directly
        // Use buildCustomCommand instead
        return [videoUrl];
    }
  }

  /// Icon representing the player
  IconData get icon {
    switch (this) {
      case LinuxExternalPlayer.systemDefault:
        return Icons.open_in_new_rounded;
      case LinuxExternalPlayer.vlc:
        return Icons.play_circle_filled_rounded;
      case LinuxExternalPlayer.mpv:
        return Icons.smart_display_rounded;
      case LinuxExternalPlayer.celluloid:
        return Icons.movie_rounded;
      case LinuxExternalPlayer.smplayer:
        return Icons.ondemand_video_rounded;
      case LinuxExternalPlayer.customCommand:
        return Icons.terminal_rounded;
    }
  }

  /// Storage key value for persistence
  String get storageKey {
    switch (this) {
      case LinuxExternalPlayer.systemDefault:
        return 'system_default';
      case LinuxExternalPlayer.vlc:
        return 'vlc';
      case LinuxExternalPlayer.mpv:
        return 'mpv';
      case LinuxExternalPlayer.celluloid:
        return 'celluloid';
      case LinuxExternalPlayer.smplayer:
        return 'smplayer';
      case LinuxExternalPlayer.customCommand:
        return 'custom_command';
    }
  }

  /// Create LinuxExternalPlayer from storage key
  static LinuxExternalPlayer fromStorageKey(String key) {
    switch (key) {
      case 'system_default':
        return LinuxExternalPlayer.systemDefault;
      case 'vlc':
        return LinuxExternalPlayer.vlc;
      case 'mpv':
        return LinuxExternalPlayer.mpv;
      case 'celluloid':
        return LinuxExternalPlayer.celluloid;
      case 'smplayer':
        return LinuxExternalPlayer.smplayer;
      case 'custom_command':
        return LinuxExternalPlayer.customCommand;
      default:
        return LinuxExternalPlayer.systemDefault;
    }
  }
}

/// Placeholder for video URL in custom command
const String linuxUrlPlaceholder = '{url}';

/// Placeholder for video title in custom command
const String linuxTitlePlaceholder = '{title}';

/// Build a custom command from a template
/// Template should contain {url} placeholder
/// Example: "vlc --fullscreen {url}"
List<String> buildLinuxCustomCommand(String template, String videoUrl, {String? title}) {
  if (template.trim().isEmpty) {
    return [];
  }

  // Replace placeholders
  String command = template
      .replaceAll(linuxUrlPlaceholder, videoUrl)
      .replaceAll(linuxTitlePlaceholder, title ?? '');

  // Parse the command into parts (handle quoted strings)
  return _parseLinuxCommand(command);
}

/// Parse a command string into executable and arguments
/// Handles quoted strings properly
List<String> _parseLinuxCommand(String command) {
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
class LinuxCustomCommandValidation {
  final bool isValid;
  final String? errorMessage;

  const LinuxCustomCommandValidation({
    required this.isValid,
    this.errorMessage,
  });

  factory LinuxCustomCommandValidation.valid() {
    return const LinuxCustomCommandValidation(isValid: true);
  }

  factory LinuxCustomCommandValidation.invalid(String message) {
    return LinuxCustomCommandValidation(isValid: false, errorMessage: message);
  }
}

LinuxCustomCommandValidation validateLinuxCustomCommand(String? command) {
  if (command == null || command.trim().isEmpty) {
    return LinuxCustomCommandValidation.invalid('Command cannot be empty');
  }

  final trimmed = command.trim();

  if (!trimmed.contains(linuxUrlPlaceholder)) {
    return LinuxCustomCommandValidation.invalid(
        'Command must contain $linuxUrlPlaceholder placeholder');
  }

  // Check for obviously invalid commands
  if (trimmed.startsWith(linuxUrlPlaceholder)) {
    return LinuxCustomCommandValidation.invalid(
        'Command must start with an executable');
  }

  return LinuxCustomCommandValidation.valid();
}
