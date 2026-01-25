import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import '../models/external_player.dart';
export '../models/external_player.dart';
import 'storage_service.dart';

/// Result of launching an external player
class ExternalPlayerLaunchResult {
  final bool success;
  final ExternalPlayer? usedPlayer;
  final String? errorMessage;

  const ExternalPlayerLaunchResult({
    required this.success,
    this.usedPlayer,
    this.errorMessage,
  });

  factory ExternalPlayerLaunchResult.succeeded(ExternalPlayer player) {
    return ExternalPlayerLaunchResult(
      success: true,
      usedPlayer: player,
    );
  }

  factory ExternalPlayerLaunchResult.failed(String message) {
    return ExternalPlayerLaunchResult(
      success: false,
      errorMessage: message,
    );
  }
}

/// Validation result for custom command
class CustomCommandValidation {
  final bool isValid;
  final String? errorMessage;

  const CustomCommandValidation({
    required this.isValid,
    this.errorMessage,
  });

  factory CustomCommandValidation.valid() {
    return const CustomCommandValidation(isValid: true);
  }

  factory CustomCommandValidation.invalid(String message) {
    return CustomCommandValidation(isValid: false, errorMessage: message);
  }
}

/// Service for detecting and launching external video players on macOS
class ExternalPlayerService {
  ExternalPlayerService._();

  /// Placeholder for video URL in custom command
  static const String urlPlaceholder = '{url}';

  /// Placeholder for video title in custom command
  static const String titlePlaceholder = '{title}';

  /// Validate a custom command template
  static CustomCommandValidation validateCustomCommand(String? command) {
    if (command == null || command.trim().isEmpty) {
      return CustomCommandValidation.invalid('Command cannot be empty');
    }

    final trimmed = command.trim();

    if (!trimmed.contains(urlPlaceholder)) {
      return CustomCommandValidation.invalid(
          'Command must contain $urlPlaceholder placeholder');
    }

    // Check for obviously invalid commands
    if (trimmed.startsWith(urlPlaceholder)) {
      return CustomCommandValidation.invalid(
          'Command must start with an executable');
    }

    return CustomCommandValidation.valid();
  }

  /// Detect which players are installed on the system
  static Future<Map<ExternalPlayer, bool>> detectInstalledPlayers() async {
    if (!Platform.isMacOS) {
      return {};
    }

    final results = <ExternalPlayer, bool>{};

    for (final player in ExternalPlayer.values) {
      if (player == ExternalPlayer.systemDefault ||
          player == ExternalPlayer.customApp ||
          player == ExternalPlayer.customCommand) {
        results[player] = true;
        continue;
      }
      results[player] = await isPlayerInstalled(player);
    }

    return results;
  }

  /// Check if a specific player is installed
  static Future<bool> isPlayerInstalled(ExternalPlayer player) async {
    if (!Platform.isMacOS) {
      return false;
    }

    switch (player) {
      case ExternalPlayer.systemDefault:
      case ExternalPlayer.customApp:
      case ExternalPlayer.customCommand:
        return true;

      case ExternalPlayer.vlc:
        return await _checkAppExists('VLC.app');

      case ExternalPlayer.iina:
        return await _checkAppExists('IINA.app');

      case ExternalPlayer.mpv:
        return await _checkCliToolExists('mpv');

      case ExternalPlayer.quickTime:
        return await _checkAppExists('QuickTime Player.app',
            systemApp: true);

      case ExternalPlayer.infuse:
        return await _checkAppExists('Infuse.app');
    }
  }

  /// Check if an .app bundle exists
  static Future<bool> _checkAppExists(String appName,
      {bool systemApp = false}) async {
    final pathsToCheck = [
      '/Applications/$appName',
      '${Platform.environment['HOME']}/Applications/$appName',
    ];

    if (systemApp) {
      pathsToCheck.add('/System/Applications/$appName');
    }

    for (final path in pathsToCheck) {
      if (await Directory(path).exists()) {
        return true;
      }
    }
    return false;
  }

  /// Check if a CLI tool exists using `which`
  static Future<bool> _checkCliToolExists(String command) async {
    try {
      final result = await Process.run('which', [command]);
      return result.exitCode == 0 &&
          (result.stdout as String).trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Launch a video URL with the user's preferred player
  static Future<ExternalPlayerLaunchResult> launchWithPreferredPlayer(
    String url, {
    String? title,
  }) async {
    if (!Platform.isMacOS) {
      // Fallback to url_launcher for non-macOS platforms
      return await _launchWithUrlLauncher(url);
    }

    // Get user's preferred player
    final preferredPlayerKey = await StorageService.getPreferredExternalPlayer();
    final preferredPlayer =
        ExternalPlayerExtension.fromStorageKey(preferredPlayerKey);

    // Try preferred player first
    if (preferredPlayer != ExternalPlayer.systemDefault) {
      final installed = await isPlayerInstalled(preferredPlayer);
      if (installed) {
        return await launchWithPlayer(url, preferredPlayer, title: title);
      }
      // If preferred player is not installed, fall through to system default
    }

    // System default fallback
    return await launchWithPlayer(url, ExternalPlayer.systemDefault,
        title: title);
  }

  /// Launch a video URL with a specific player
  static Future<ExternalPlayerLaunchResult> launchWithPlayer(
    String url,
    ExternalPlayer player, {
    String? title,
  }) async {
    if (!Platform.isMacOS) {
      return await _launchWithUrlLauncher(url);
    }

    try {
      switch (player) {
        case ExternalPlayer.systemDefault:
          return await _launchSystemDefault(url);

        case ExternalPlayer.customApp:
          return await _launchCustomApp(url);

        case ExternalPlayer.customCommand:
          return await _launchCustomCommand(url, title: title);

        case ExternalPlayer.mpv:
          return await _launchMpv(url, title: title);

        default:
          return await _launchMacOSApp(url, player);
      }
    } catch (e) {
      // Fallback to url_launcher
      try {
        final result = await _launchWithUrlLauncher(url);
        if (result.success) {
          return ExternalPlayerLaunchResult.succeeded(
              ExternalPlayer.systemDefault);
        }
        return result;
      } catch (_) {
        return ExternalPlayerLaunchResult.failed(
            'Failed to open external player: $e');
      }
    }
  }

  /// Launch with system default (open url)
  static Future<ExternalPlayerLaunchResult> _launchSystemDefault(
      String url) async {
    try {
      final result = await Process.run('open', [url]);
      if (result.exitCode == 0) {
        return ExternalPlayerLaunchResult.succeeded(
            ExternalPlayer.systemDefault);
      }
      return ExternalPlayerLaunchResult.failed(
          'Failed to open with system default: ${result.stderr}');
    } catch (e) {
      return ExternalPlayerLaunchResult.failed(
          'Failed to open with system default: $e');
    }
  }

  /// Launch with a macOS .app bundle
  static Future<ExternalPlayerLaunchResult> _launchMacOSApp(
    String url,
    ExternalPlayer player,
  ) async {
    final appName = player.macOSAppName;
    if (appName == null) {
      return ExternalPlayerLaunchResult.failed(
          '${player.displayName} is not a valid app bundle');
    }

    try {
      final result = await Process.run('open', ['-a', appName, url]);
      if (result.exitCode == 0) {
        return ExternalPlayerLaunchResult.succeeded(player);
      }
      // If app not found, try system default
      return await _launchSystemDefault(url);
    } catch (e) {
      return ExternalPlayerLaunchResult.failed(
          'Failed to open with ${player.displayName}: $e');
    }
  }

  /// Launch with mpv CLI
  static Future<ExternalPlayerLaunchResult> _launchMpv(
    String url, {
    String? title,
  }) async {
    try {
      final args = <String>[url];
      if (title != null && title.isNotEmpty) {
        args.addAll(['--title=$title']);
      }

      // Run mpv detached so it doesn't block
      await Process.start('mpv', args, mode: ProcessStartMode.detached);
      return ExternalPlayerLaunchResult.succeeded(ExternalPlayer.mpv);
    } catch (e) {
      // mpv not found, fall back to system default
      return await _launchSystemDefault(url);
    }
  }

  /// Launch with custom app path
  static Future<ExternalPlayerLaunchResult> _launchCustomApp(
      String url) async {
    final customPath = await StorageService.getCustomExternalPlayerPath();
    if (customPath == null || customPath.isEmpty) {
      return ExternalPlayerLaunchResult.failed(
          'Custom app path not configured');
    }

    try {
      // Check if it's an .app bundle or executable
      if (customPath.endsWith('.app')) {
        final result = await Process.run('open', ['-a', customPath, url]);
        if (result.exitCode == 0) {
          return ExternalPlayerLaunchResult.succeeded(ExternalPlayer.customApp);
        }
        return ExternalPlayerLaunchResult.failed(
            'Failed to open custom app: ${result.stderr}');
      } else {
        // Assume it's an executable
        await Process.start(customPath, [url], mode: ProcessStartMode.detached);
        return ExternalPlayerLaunchResult.succeeded(ExternalPlayer.customApp);
      }
    } catch (e) {
      return ExternalPlayerLaunchResult.failed(
          'Failed to open custom app: $e');
    }
  }

  /// Launch with custom command template
  static Future<ExternalPlayerLaunchResult> _launchCustomCommand(
    String url, {
    String? title,
  }) async {
    final commandTemplate = await StorageService.getCustomExternalPlayerCommand();

    // Validate command
    final validation = validateCustomCommand(commandTemplate);
    if (!validation.isValid) {
      return ExternalPlayerLaunchResult.failed(
          validation.errorMessage ?? 'Invalid custom command');
    }

    try {
      // Replace placeholders
      String command = commandTemplate!
          .replaceAll(urlPlaceholder, url)
          .replaceAll(titlePlaceholder, title ?? '');

      // Parse the command into executable and arguments
      final parts = _parseCommand(command);
      if (parts.isEmpty) {
        return ExternalPlayerLaunchResult.failed('Invalid command format');
      }

      final executable = parts.first;
      final args = parts.skip(1).toList();

      // Use Process.run for commands like 'open' that spawn and exit
      // Use Process.start for direct executables that need to stay running
      if (executable == 'open') {
        final result = await Process.run(executable, args);
        if (result.exitCode == 0) {
          return ExternalPlayerLaunchResult.succeeded(ExternalPlayer.customCommand);
        }
        return ExternalPlayerLaunchResult.failed(
            'Command failed: ${result.stderr}');
      } else {
        // For direct executables (vlc, mpv, etc.), run detached
        await Process.start(executable, args, mode: ProcessStartMode.detached);
        return ExternalPlayerLaunchResult.succeeded(ExternalPlayer.customCommand);
      }
    } catch (e) {
      return ExternalPlayerLaunchResult.failed(
          'Failed to execute custom command: $e');
    }
  }

  /// Parse a command string into executable and arguments
  /// Handles quoted strings properly
  static List<String> _parseCommand(String command) {
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

  /// Fallback to url_launcher
  static Future<ExternalPlayerLaunchResult> _launchWithUrlLauncher(
      String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
        return ExternalPlayerLaunchResult.succeeded(
            ExternalPlayer.systemDefault);
      }
      return ExternalPlayerLaunchResult.failed(
          'Could not open external player');
    } catch (e) {
      return ExternalPlayerLaunchResult.failed(
          'Failed to launch URL: $e');
    }
  }
}
