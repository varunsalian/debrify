import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/external_player.dart';
import '../models/ios_external_player.dart';
import '../models/linux_external_player.dart';
import '../models/windows_external_player.dart';
export '../models/external_player.dart';
export '../models/ios_external_player.dart';
export '../models/linux_external_player.dart';
export '../models/windows_external_player.dart';
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

  // ============================================================
  // iOS External Player Support
  // ============================================================

  /// Check if an iOS player is likely installed by checking if we can open its URL scheme
  static Future<bool> isIOSPlayerInstalled(iOSExternalPlayer player) async {
    if (!Platform.isIOS) return false;
    if (player == iOSExternalPlayer.customScheme) return true;

    try {
      final schemeUrl = Uri.parse(player.urlScheme);
      return await canLaunchUrl(schemeUrl);
    } catch (e) {
      debugPrint('Error checking iOS player installation: $e');
      return false;
    }
  }

  /// Detect which iOS players are installed
  static Future<Map<iOSExternalPlayer, bool>> detectInstalledIOSPlayers() async {
    if (!Platform.isIOS) return {};

    final results = <iOSExternalPlayer, bool>{};

    for (final player in iOSExternalPlayer.values) {
      if (player == iOSExternalPlayer.customScheme) {
        results[player] = true; // Custom is always "available"
        continue;
      }
      results[player] = await isIOSPlayerInstalled(player);
    }

    return results;
  }

  /// Launch video with preferred iOS player
  static Future<iOSExternalPlayerLaunchResult> launchWithPreferredIOSPlayer(
    String url, {
    String? title,
  }) async {
    if (!Platform.isIOS) {
      return iOSExternalPlayerLaunchResult.failed('Not running on iOS');
    }

    // Get user's preferred iOS player
    final preferredPlayerKey = await StorageService.getPreferredIOSExternalPlayer();
    final preferredPlayer = iOSExternalPlayerExtension.fromStorageKey(preferredPlayerKey);

    return await launchWithIOSPlayer(url, preferredPlayer, title: title);
  }

  /// Launch video with a specific iOS player
  static Future<iOSExternalPlayerLaunchResult> launchWithIOSPlayer(
    String url,
    iOSExternalPlayer player, {
    String? title,
  }) async {
    if (!Platform.isIOS) {
      return iOSExternalPlayerLaunchResult.failed('Not running on iOS');
    }

    try {
      String playerUrl;

      if (player == iOSExternalPlayer.customScheme) {
        // Use custom URL scheme template
        final customTemplate = await StorageService.getIOSCustomSchemeTemplate();
        if (customTemplate == null || customTemplate.isEmpty) {
          return iOSExternalPlayerLaunchResult.failed(
            'Custom URL scheme not configured',
          );
        }

        final validation = validateCustomScheme(customTemplate);
        if (!validation.isValid) {
          return iOSExternalPlayerLaunchResult.failed(
            validation.errorMessage ?? 'Invalid custom URL scheme',
          );
        }

        playerUrl = buildCustomSchemeLaunchUrl(customTemplate, url);
      } else {
        playerUrl = player.buildLaunchUrl(url);
      }

      debugPrint('iOS External Player: Launching with URL: $playerUrl');

      final uri = Uri.parse(playerUrl);

      // For custom schemes, skip canLaunchUrl check (it would fail since
      // custom schemes aren't in LSApplicationQueriesSchemes)
      // Just try to launch and let iOS handle if app isn't installed
      if (player == iOSExternalPlayer.customScheme) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return iOSExternalPlayerLaunchResult.succeeded(player);
      }

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return iOSExternalPlayerLaunchResult.succeeded(player);
      } else {
        // Player not installed
        return iOSExternalPlayerLaunchResult.failed(
          '${player.displayName} is not installed. Please install it from the App Store.',
        );
      }
    } catch (e) {
      debugPrint('iOS External Player: Launch failed: $e');
      return iOSExternalPlayerLaunchResult.failed(
        'Failed to open ${player.displayName}: $e',
      );
    }
  }
}

/// Result of launching an iOS external player
class iOSExternalPlayerLaunchResult {
  final bool success;
  final iOSExternalPlayer? usedPlayer;
  final String? errorMessage;

  const iOSExternalPlayerLaunchResult({
    required this.success,
    this.usedPlayer,
    this.errorMessage,
  });

  factory iOSExternalPlayerLaunchResult.succeeded(iOSExternalPlayer player) {
    return iOSExternalPlayerLaunchResult(
      success: true,
      usedPlayer: player,
    );
  }

  factory iOSExternalPlayerLaunchResult.failed(String message) {
    return iOSExternalPlayerLaunchResult(
      success: false,
      errorMessage: message,
    );
  }
}

// ============================================================
// Linux External Player Support
// ============================================================

/// Result of launching a Linux external player
class LinuxExternalPlayerLaunchResult {
  final bool success;
  final LinuxExternalPlayer? usedPlayer;
  final String? errorMessage;

  const LinuxExternalPlayerLaunchResult({
    required this.success,
    this.usedPlayer,
    this.errorMessage,
  });

  factory LinuxExternalPlayerLaunchResult.succeeded(LinuxExternalPlayer player) {
    return LinuxExternalPlayerLaunchResult(
      success: true,
      usedPlayer: player,
    );
  }

  factory LinuxExternalPlayerLaunchResult.failed(String message) {
    return LinuxExternalPlayerLaunchResult(
      success: false,
      errorMessage: message,
    );
  }
}

/// Extension methods for Linux external player support
extension LinuxExternalPlayerServiceExtension on ExternalPlayerService {
  /// Check if a Linux player is installed using `which` command
  static Future<bool> isLinuxPlayerInstalled(LinuxExternalPlayer player) async {
    if (!Platform.isLinux) return false;
    if (player == LinuxExternalPlayer.customCommand) return true;
    if (player == LinuxExternalPlayer.systemDefault) return true;

    try {
      final result = await Process.run('which', [player.executable]);
      return result.exitCode == 0 &&
          (result.stdout as String).trim().isNotEmpty;
    } catch (e) {
      debugPrint('Error checking Linux player installation: $e');
      return false;
    }
  }

  /// Detect which Linux players are installed
  static Future<Map<LinuxExternalPlayer, bool>> detectInstalledLinuxPlayers() async {
    if (!Platform.isLinux) return {};

    final results = <LinuxExternalPlayer, bool>{};

    for (final player in LinuxExternalPlayer.values) {
      if (player == LinuxExternalPlayer.customCommand ||
          player == LinuxExternalPlayer.systemDefault) {
        results[player] = true;
        continue;
      }
      results[player] = await isLinuxPlayerInstalled(player);
    }

    return results;
  }

  /// Launch video with preferred Linux player
  static Future<LinuxExternalPlayerLaunchResult> launchWithPreferredLinuxPlayer(
    String url, {
    String? title,
  }) async {
    if (!Platform.isLinux) {
      return LinuxExternalPlayerLaunchResult.failed('Not running on Linux');
    }

    // Get user's preferred Linux player
    final preferredPlayerKey = await StorageService.getPreferredLinuxExternalPlayer();
    final preferredPlayer = LinuxExternalPlayerExtension.fromStorageKey(preferredPlayerKey);

    // Check if preferred player is installed
    if (preferredPlayer != LinuxExternalPlayer.systemDefault &&
        preferredPlayer != LinuxExternalPlayer.customCommand) {
      final installed = await isLinuxPlayerInstalled(preferredPlayer);
      if (!installed) {
        // Fall back to system default
        return await launchWithLinuxPlayer(
          url,
          LinuxExternalPlayer.systemDefault,
          title: title,
        );
      }
    }

    return await launchWithLinuxPlayer(url, preferredPlayer, title: title);
  }

  /// Launch video with a specific Linux player
  static Future<LinuxExternalPlayerLaunchResult> launchWithLinuxPlayer(
    String url,
    LinuxExternalPlayer player, {
    String? title,
  }) async {
    if (!Platform.isLinux) {
      return LinuxExternalPlayerLaunchResult.failed('Not running on Linux');
    }

    try {
      List<String> command;

      if (player == LinuxExternalPlayer.customCommand) {
        // Use custom command template
        final customTemplate = await StorageService.getLinuxCustomCommand();
        if (customTemplate == null || customTemplate.isEmpty) {
          return LinuxExternalPlayerLaunchResult.failed(
            'Custom command not configured',
          );
        }

        final validation = validateLinuxCustomCommand(customTemplate);
        if (!validation.isValid) {
          return LinuxExternalPlayerLaunchResult.failed(
            validation.errorMessage ?? 'Invalid custom command',
          );
        }

        command = buildLinuxCustomCommand(customTemplate, url, title: title);
        if (command.isEmpty) {
          return LinuxExternalPlayerLaunchResult.failed('Invalid command format');
        }
      } else {
        command = player.buildCommand(url, title: title);
      }

      debugPrint('Linux External Player: Launching with command: ${command.join(' ')}');

      final executable = command.first;
      final args = command.skip(1).toList();

      // For xdg-open, use Process.run as it spawns and exits quickly
      // For media players, use Process.start detached so they run independently
      if (executable == 'xdg-open') {
        final result = await Process.run(executable, args);
        if (result.exitCode == 0) {
          return LinuxExternalPlayerLaunchResult.succeeded(player);
        }
        return LinuxExternalPlayerLaunchResult.failed(
          'Failed to open with system default: ${result.stderr}',
        );
      } else {
        // Run player detached so it doesn't block
        await Process.start(
          executable,
          args,
          mode: ProcessStartMode.detached,
        );
        return LinuxExternalPlayerLaunchResult.succeeded(player);
      }
    } catch (e) {
      debugPrint('Linux External Player: Launch failed: $e');
      return LinuxExternalPlayerLaunchResult.failed(
        'Failed to open ${player.displayName}: $e',
      );
    }
  }
}

// ============================================================
// Windows External Player Support
// ============================================================

/// Result of launching a Windows external player
class WindowsExternalPlayerLaunchResult {
  final bool success;
  final WindowsExternalPlayer? usedPlayer;
  final String? errorMessage;

  const WindowsExternalPlayerLaunchResult({
    required this.success,
    this.usedPlayer,
    this.errorMessage,
  });

  factory WindowsExternalPlayerLaunchResult.succeeded(WindowsExternalPlayer player) {
    return WindowsExternalPlayerLaunchResult(
      success: true,
      usedPlayer: player,
    );
  }

  factory WindowsExternalPlayerLaunchResult.failed(String message) {
    return WindowsExternalPlayerLaunchResult(
      success: false,
      errorMessage: message,
    );
  }
}

/// Extension methods for Windows external player support
extension WindowsExternalPlayerServiceExtension on ExternalPlayerService {
  /// Check if a Windows player is installed
  /// Uses `where` command (Windows equivalent of `which`)
  /// Also checks common installation paths for players not typically in PATH
  static Future<bool> isWindowsPlayerInstalled(WindowsExternalPlayer player) async {
    if (!Platform.isWindows) return false;
    if (player == WindowsExternalPlayer.customCommand) return true;
    if (player == WindowsExternalPlayer.systemDefault) return true;

    // First, try `where` command (checks PATH)
    try {
      final result = await Process.run('where', [player.executable]);
      if (result.exitCode == 0 &&
          (result.stdout as String).trim().isNotEmpty) {
        return true;
      }
    } catch (e) {
      debugPrint('Windows player PATH check failed: $e');
    }

    // If not in PATH, check common installation paths
    final commonPaths = player.commonPaths;
    for (final path in commonPaths) {
      // Handle ${USER} placeholder in paths
      String resolvedPath = path;
      if (path.contains(r'${USER}')) {
        final username = Platform.environment['USERNAME'] ?? '';
        resolvedPath = path.replaceAll(r'${USER}', username);
      }

      try {
        if (await File(resolvedPath).exists()) {
          return true;
        }
      } catch (e) {
        // Path check failed, continue to next
      }
    }

    return false;
  }

  /// Find the resolved path for a Windows player
  /// Returns the full path if found in common locations, or executable name if in PATH
  static Future<String?> _resolveWindowsPlayerPath(WindowsExternalPlayer player) async {
    if (!Platform.isWindows) return null;

    // First, try `where` command (checks PATH)
    try {
      final result = await Process.run('where', [player.executable]);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split('\n').first.trim();
        if (path.isNotEmpty) {
          return path;
        }
      }
    } catch (e) {
      // Not in PATH
    }

    // Check common installation paths
    final commonPaths = player.commonPaths;
    for (final path in commonPaths) {
      String resolvedPath = path;
      if (path.contains(r'${USER}')) {
        final username = Platform.environment['USERNAME'] ?? '';
        resolvedPath = path.replaceAll(r'${USER}', username);
      }

      try {
        if (await File(resolvedPath).exists()) {
          return resolvedPath;
        }
      } catch (e) {
        // Continue to next path
      }
    }

    return null;
  }

  /// Detect which Windows players are installed
  static Future<Map<WindowsExternalPlayer, bool>> detectInstalledWindowsPlayers() async {
    if (!Platform.isWindows) return {};

    final results = <WindowsExternalPlayer, bool>{};

    for (final player in WindowsExternalPlayer.values) {
      if (player == WindowsExternalPlayer.customCommand ||
          player == WindowsExternalPlayer.systemDefault) {
        results[player] = true;
        continue;
      }
      results[player] = await isWindowsPlayerInstalled(player);
    }

    return results;
  }

  /// Launch video with preferred Windows player
  static Future<WindowsExternalPlayerLaunchResult> launchWithPreferredWindowsPlayer(
    String url, {
    String? title,
  }) async {
    if (!Platform.isWindows) {
      return WindowsExternalPlayerLaunchResult.failed('Not running on Windows');
    }

    // Get user's preferred Windows player
    final preferredPlayerKey = await StorageService.getPreferredWindowsExternalPlayer();
    final preferredPlayer = WindowsExternalPlayerExtension.fromStorageKey(preferredPlayerKey);

    // Check if preferred player is installed
    if (preferredPlayer != WindowsExternalPlayer.systemDefault &&
        preferredPlayer != WindowsExternalPlayer.customCommand) {
      final installed = await isWindowsPlayerInstalled(preferredPlayer);
      if (!installed) {
        // Fall back to system default
        return await launchWithWindowsPlayer(
          url,
          WindowsExternalPlayer.systemDefault,
          title: title,
        );
      }
    }

    return await launchWithWindowsPlayer(url, preferredPlayer, title: title);
  }

  /// Launch video with a specific Windows player
  static Future<WindowsExternalPlayerLaunchResult> launchWithWindowsPlayer(
    String url,
    WindowsExternalPlayer player, {
    String? title,
  }) async {
    if (!Platform.isWindows) {
      return WindowsExternalPlayerLaunchResult.failed('Not running on Windows');
    }

    try {
      List<String> command;
      String? resolvedPath;

      if (player == WindowsExternalPlayer.customCommand) {
        // Use custom command template
        final customTemplate = await StorageService.getWindowsCustomCommand();
        if (customTemplate == null || customTemplate.isEmpty) {
          return WindowsExternalPlayerLaunchResult.failed(
            'Custom command not configured',
          );
        }

        final validation = validateWindowsCustomCommand(customTemplate);
        if (!validation.isValid) {
          return WindowsExternalPlayerLaunchResult.failed(
            validation.errorMessage ?? 'Invalid custom command',
          );
        }

        command = buildWindowsCustomCommand(customTemplate, url, title: title);
        if (command.isEmpty) {
          return WindowsExternalPlayerLaunchResult.failed('Invalid command format');
        }
      } else {
        // For non-system-default players, try to resolve full path
        if (player != WindowsExternalPlayer.systemDefault) {
          resolvedPath = await _resolveWindowsPlayerPath(player);
        }
        command = player.buildCommand(url, title: title, resolvedPath: resolvedPath);
      }

      debugPrint('Windows External Player: Launching with command: ${command.join(' ')}');

      final executable = command.first;
      final args = command.skip(1).toList();

      // For explorer.exe (system default), use Process.run as it spawns and exits quickly
      // For media players, use Process.start detached so they run independently
      if (executable == 'explorer.exe') {
        final result = await Process.run(executable, args);
        if (result.exitCode == 0 || result.exitCode == 1) {
          // explorer.exe may return 1 even on success for URL launching
          return WindowsExternalPlayerLaunchResult.succeeded(player);
        }
        return WindowsExternalPlayerLaunchResult.failed(
          'Failed to open with system default: ${result.stderr}',
        );
      } else {
        // Run player detached so it doesn't block
        await Process.start(
          executable,
          args,
          mode: ProcessStartMode.detached,
        );
        return WindowsExternalPlayerLaunchResult.succeeded(player);
      }
    } catch (e) {
      debugPrint('Windows External Player: Launch failed: $e');
      return WindowsExternalPlayerLaunchResult.failed(
        'Failed to open ${player.displayName}: $e',
      );
    }
  }
}
