import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'remote_constants.dart';
import '../../services/stremio_service.dart';
import '../../services/storage_service.dart';
import '../../services/account_service.dart';
import '../../services/torbox_account_service.dart';
import '../../services/pikpak_api_service.dart';
import '../../services/engine/remote_engine_manager.dart';
import '../../services/engine/local_engine_storage.dart';

/// Callback type for remote command handlers
typedef RemoteCommandCallback = void Function(String action, String command, String? data);

/// Android KeyEvent key codes
class AndroidKeyCode {
  static const int dpadUp = 19;
  static const int dpadDown = 20;
  static const int dpadLeft = 21;
  static const int dpadRight = 22;
  static const int dpadCenter = 23;
  static const int back = 4;
  static const int mediaPlayPause = 85;
  static const int mediaFastForward = 90;
  static const int mediaRewind = 89;
}

/// Routes UDP remote commands to registered handlers
///
/// Uses platform channels on Android TV to inject real key events,
/// which works with all widgets that respond to D-pad input.
class RemoteCommandRouter {
  // Singleton
  static final RemoteCommandRouter _instance = RemoteCommandRouter._internal();
  factory RemoteCommandRouter() => _instance;
  RemoteCommandRouter._internal();

  // Platform channel for key injection
  static const _channel = MethodChannel('com.debrify.app/remote_control');

  // Registered command handlers
  final List<RemoteCommandCallback> _handlers = [];

  // Navigator key for back navigation
  GlobalKey<NavigatorState>? _navigatorKey;

  // Scaffold messenger key for showing snackbars
  GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;

  // Callback to restart app flow (set by main.dart)
  VoidCallback? _onRestartApp;

  /// Set the navigator key for back navigation
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Set the scaffold messenger key for showing snackbars
  void setScaffoldMessengerKey(GlobalKey<ScaffoldMessengerState> key) {
    _scaffoldMessengerKey = key;
  }

  /// Set the callback to restart the app flow
  void setRestartCallback(VoidCallback callback) {
    _onRestartApp = callback;
  }

  /// Show a snackbar message (TV feedback)
  void _showSnackBar(String message, {bool isError = false}) {
    final messenger = _scaffoldMessengerKey?.currentState;
    if (messenger == null) return;

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Register a command handler
  void addHandler(RemoteCommandCallback handler) {
    if (!_handlers.contains(handler)) {
      _handlers.add(handler);
      debugPrint('RemoteCommandRouter: Handler registered');
    }
  }

  /// Remove a command handler
  void removeHandler(RemoteCommandCallback handler) {
    _handlers.remove(handler);
    debugPrint('RemoteCommandRouter: Handler removed');
  }

  /// Dispatch a remote command to all registered handlers
  void dispatchCommand(String action, String command, String? data) {
    debugPrint('RemoteCommandRouter: Dispatching $action:$command${data != null ? ' with data' : ''} to ${_handlers.length} handlers');

    for (final handler in _handlers.toList()) {
      try {
        handler(action, command, data);
      } catch (e) {
        debugPrint('RemoteCommandRouter: Handler error: $e');
      }
    }

    // Handle addon commands (TV side)
    if (action == RemoteAction.addon) {
      _handleAddonCommand(command, data);
      return;
    }

    // Handle text input commands (TV side)
    if (action == RemoteAction.text) {
      _handleTextCommand(command, data);
      return;
    }

    // Handle config commands (TV side)
    if (action == RemoteAction.config) {
      _handleConfigCommand(command, data);
      return;
    }

    // Also try to use the focus system for navigation
    _tryFocusNavigation(action, command);
  }

  /// Handle addon commands on TV
  Future<void> _handleAddonCommand(String command, String? data) async {
    if (command == AddonCommand.install && data != null) {
      debugPrint('RemoteCommandRouter: Installing addon from $data');
      try {
        final addon = await StremioService.instance.addAddon(data);
        debugPrint('RemoteCommandRouter: Addon installed: ${addon.name}');
        _showSnackBar('Addon installed: ${addon.name}');
      } catch (e) {
        debugPrint('RemoteCommandRouter: Failed to install addon: $e');
        _showSnackBar('Failed to install addon', isError: true);
      }
    }
  }

  /// Handle text input commands on TV
  Future<void> _handleTextCommand(String command, String? data) async {
    if (!Platform.isAndroid) {
      debugPrint('RemoteCommandRouter: Text input only supported on Android');
      return;
    }

    try {
      switch (command) {
        case TextCommand.type:
          if (data != null && data.isNotEmpty) {
            await _channel.invokeMethod('injectText', {'text': data});
            debugPrint('RemoteCommandRouter: Injected text: $data');
          }
          break;
        case TextCommand.backspace:
          // Send backspace key event
          await _channel.invokeMethod('injectKeyEvent', {'keyCode': 67}); // KEYCODE_DEL
          debugPrint('RemoteCommandRouter: Injected backspace');
          break;
        case TextCommand.clear:
          // Select all (Ctrl+A) then delete
          await _channel.invokeMethod('injectText', {'text': '', 'clear': true});
          debugPrint('RemoteCommandRouter: Cleared text field');
          break;
      }
    } catch (e) {
      debugPrint('RemoteCommandRouter: Failed to handle text command: $e');
    }
  }

  /// Handle config commands on TV (credentials/setup from phone)
  Future<void> _handleConfigCommand(String command, String? data) async {
    debugPrint('RemoteCommandRouter: Handling config command: $command');

    // Handle complete signal (doesn't need data)
    if (command == ConfigCommand.complete) {
      await _handleConfigComplete();
      return;
    }

    if (data == null) {
      debugPrint('RemoteCommandRouter: Config command missing data');
      return;
    }

    switch (command) {
      case ConfigCommand.realDebrid:
        await _handleRealDebridConfig(data);
        break;
      case ConfigCommand.torbox:
        await _handleTorboxConfig(data);
        break;
      case ConfigCommand.pikpak:
        await _handlePikPakConfig(data);
        break;
      case ConfigCommand.searchEngines:
        await _handleSearchEnginesConfig(data);
        break;
      default:
        debugPrint('RemoteCommandRouter: Unknown config command: $command');
    }
  }

  /// Handle Real-Debrid API key config
  Future<void> _handleRealDebridConfig(String apiKey) async {
    try {
      debugPrint('RemoteCommandRouter: Validating Real-Debrid API key...');

      // Validate the API key
      final isValid = await AccountService.validateAndGetUserInfo(apiKey);
      if (!isValid) {
        _showSnackBar('Real-Debrid: Invalid API key', isError: true);
        return;
      }

      // Save the API key
      await StorageService.saveApiKey(apiKey);
      await StorageService.setRealDebridIntegrationEnabled(true);

      debugPrint('RemoteCommandRouter: Real-Debrid configured successfully');
      _showSnackBar('Real-Debrid configured successfully');
    } catch (e) {
      debugPrint('RemoteCommandRouter: Failed to configure Real-Debrid: $e');
      _showSnackBar('Real-Debrid: Configuration failed', isError: true);
    }
  }

  /// Handle Torbox API key config
  Future<void> _handleTorboxConfig(String apiKey) async {
    try {
      debugPrint('RemoteCommandRouter: Validating Torbox API key...');

      // Validate the API key
      final isValid = await TorboxAccountService.validateAndGetUserInfo(apiKey);
      if (!isValid) {
        _showSnackBar('Torbox: Invalid API key', isError: true);
        return;
      }

      // Save the API key
      await StorageService.saveTorboxApiKey(apiKey);
      await StorageService.setTorboxIntegrationEnabled(true);

      debugPrint('RemoteCommandRouter: Torbox configured successfully');
      _showSnackBar('Torbox configured successfully');
    } catch (e) {
      debugPrint('RemoteCommandRouter: Failed to configure Torbox: $e');
      _showSnackBar('Torbox: Configuration failed', isError: true);
    }
  }

  /// Handle PikPak credentials config
  Future<void> _handlePikPakConfig(String jsonData) async {
    try {
      debugPrint('RemoteCommandRouter: Configuring PikPak...');

      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final email = data['email'] as String?;
      final password = data['password'] as String?;

      if (email == null || password == null) {
        _showSnackBar('PikPak: Invalid credentials data', isError: true);
        return;
      }

      // Attempt login
      final result = await PikPakApiService.instance.login(email, password);
      if (!result) {
        _showSnackBar('PikPak: Login failed', isError: true);
        return;
      }

      // Enable PikPak integration
      await StorageService.setPikPakEnabled(true);

      debugPrint('RemoteCommandRouter: PikPak configured successfully');
      _showSnackBar('PikPak configured successfully');
    } catch (e) {
      debugPrint('RemoteCommandRouter: Failed to configure PikPak: $e');
      _showSnackBar('PikPak: Configuration failed', isError: true);
    }
  }

  /// Handle config complete signal - mark onboarding done and restart app flow
  Future<void> _handleConfigComplete() async {
    debugPrint('RemoteCommandRouter: Config complete, restarting app flow...');

    // Mark onboarding as complete
    await StorageService.setInitialSetupComplete(true);

    // Show snackbar
    _showSnackBar('Setup received! Restarting...');

    // Give snackbar time to show, then restart app
    await Future.delayed(const Duration(milliseconds: 1500));

    // Use the restart callback if available
    if (_onRestartApp != null) {
      _onRestartApp!();
      debugPrint('RemoteCommandRouter: Restart callback invoked');
    } else {
      debugPrint('RemoteCommandRouter: Restart callback not available');
    }
  }

  /// Handle search engines config (downloads engine IDs)
  Future<void> _handleSearchEnginesConfig(String jsonData) async {
    try {
      debugPrint('RemoteCommandRouter: Configuring search engines...');

      final engineIds = (jsonDecode(jsonData) as List).cast<String>();
      if (engineIds.isEmpty) {
        debugPrint('RemoteCommandRouter: No engine IDs to import');
        return;
      }

      final remoteManager = RemoteEngineManager();
      final localStorage = LocalEngineStorage.instance;
      await localStorage.initialize();

      // Fetch available engines
      final availableEngines = await remoteManager.fetchAvailableEngines();
      int successCount = 0;
      int failCount = 0;

      for (final engineId in engineIds) {
        // Find the engine info
        final engineInfo = availableEngines.where((e) => e.id == engineId).firstOrNull;
        if (engineInfo == null) {
          debugPrint('RemoteCommandRouter: Engine $engineId not found');
          failCount++;
          continue;
        }

        // Check if already imported
        if (await localStorage.isEngineImported(engineId)) {
          debugPrint('RemoteCommandRouter: Engine $engineId already imported');
          successCount++;
          continue;
        }

        // Download and save the engine
        try {
          final yamlContent = await remoteManager.downloadEngineYaml(engineInfo.fileName);
          if (yamlContent == null) {
            debugPrint('RemoteCommandRouter: Failed to download engine $engineId');
            failCount++;
            continue;
          }
          await localStorage.saveEngine(
            engineId: engineId,
            fileName: engineInfo.fileName,
            yamlContent: yamlContent,
            displayName: engineInfo.displayName,
            icon: engineInfo.icon,
          );
          successCount++;
        } catch (e) {
          debugPrint('RemoteCommandRouter: Failed to import engine $engineId: $e');
          failCount++;
        }
      }

      if (failCount == 0) {
        _showSnackBar('$successCount search engine${successCount != 1 ? 's' : ''} configured');
      } else if (successCount == 0) {
        _showSnackBar('Search engines: All failed to import', isError: true);
      } else {
        _showSnackBar('Search engines: $successCount imported, $failCount failed', isError: true);
      }
    } catch (e) {
      debugPrint('RemoteCommandRouter: Failed to configure search engines: $e');
      _showSnackBar('Search engines: Configuration failed', isError: true);
    }
  }

  /// Try to handle navigation commands via platform key injection (Android) or focus system (other platforms)
  void _tryFocusNavigation(String action, String command) {
    // On Android, use platform channel to inject real key events
    if (Platform.isAndroid) {
      _injectKeyEvent(action, command);
      return;
    }

    // Fallback for non-Android platforms: use focus system
    if (action != RemoteAction.navigate) return;

    final primaryFocus = FocusManager.instance.primaryFocus;

    switch (command) {
      case NavigateCommand.up:
        primaryFocus?.focusInDirection(TraversalDirection.up);
        break;
      case NavigateCommand.down:
        primaryFocus?.focusInDirection(TraversalDirection.down);
        break;
      case NavigateCommand.left:
        primaryFocus?.focusInDirection(TraversalDirection.left);
        break;
      case NavigateCommand.right:
        primaryFocus?.focusInDirection(TraversalDirection.right);
        break;
      case NavigateCommand.select:
        _activateFocusedElement(primaryFocus);
        break;
      case NavigateCommand.back:
        _handleBack();
        break;
    }
  }

  /// Inject a key event via platform channel (Android only)
  Future<void> _injectKeyEvent(String action, String command) async {
    final keyCode = _commandToAndroidKeyCode(action, command);
    if (keyCode == null) {
      debugPrint('RemoteCommandRouter: No key code mapping for $action:$command');
      return;
    }

    try {
      await _channel.invokeMethod('injectKeyEvent', {'keyCode': keyCode});
      debugPrint('RemoteCommandRouter: Injected key event $keyCode for $action:$command');
    } catch (e) {
      debugPrint('RemoteCommandRouter: Failed to inject key event: $e');
      // Fallback to focus-based navigation if platform channel fails
      _fallbackFocusNavigation(action, command);
    }
  }

  /// Map command to Android KeyEvent key code
  int? _commandToAndroidKeyCode(String action, String command) {
    if (action == RemoteAction.navigate) {
      switch (command) {
        case NavigateCommand.up:
          return AndroidKeyCode.dpadUp;
        case NavigateCommand.down:
          return AndroidKeyCode.dpadDown;
        case NavigateCommand.left:
          return AndroidKeyCode.dpadLeft;
        case NavigateCommand.right:
          return AndroidKeyCode.dpadRight;
        case NavigateCommand.select:
          return AndroidKeyCode.dpadCenter;
        case NavigateCommand.back:
          return AndroidKeyCode.back;
      }
    } else if (action == RemoteAction.media) {
      switch (command) {
        case MediaCommand.playPause:
          return AndroidKeyCode.mediaPlayPause;
        case MediaCommand.seekForward:
          return AndroidKeyCode.mediaFastForward;
        case MediaCommand.seekBackward:
          return AndroidKeyCode.mediaRewind;
      }
    }
    return null;
  }

  /// Fallback focus-based navigation for when platform channel fails
  void _fallbackFocusNavigation(String action, String command) {
    if (action != RemoteAction.navigate) return;

    final primaryFocus = FocusManager.instance.primaryFocus;

    switch (command) {
      case NavigateCommand.up:
        primaryFocus?.focusInDirection(TraversalDirection.up);
        break;
      case NavigateCommand.down:
        primaryFocus?.focusInDirection(TraversalDirection.down);
        break;
      case NavigateCommand.left:
        primaryFocus?.focusInDirection(TraversalDirection.left);
        break;
      case NavigateCommand.right:
        primaryFocus?.focusInDirection(TraversalDirection.right);
        break;
      case NavigateCommand.select:
        _activateFocusedElement(primaryFocus);
        break;
      case NavigateCommand.back:
        _handleBack();
        break;
    }
  }

  /// Activate the currently focused element using Flutter's Actions system
  void _activateFocusedElement(FocusNode? focus) {
    final context = focus?.context;
    if (context == null) {
      debugPrint('RemoteCommandRouter: No focused element to activate');
      return;
    }

    debugPrint('RemoteCommandRouter: Activating focused element');

    // Try to invoke ActivateIntent - this works for buttons, list tiles, etc.
    final result = Actions.maybeInvoke<Intent>(context, const ActivateIntent());
    if (result != null) {
      debugPrint('RemoteCommandRouter: ActivateIntent handled');
      return;
    }

    // Fallback: Try ButtonActivateIntent for buttons specifically
    final buttonResult = Actions.maybeInvoke<Intent>(context, const ButtonActivateIntent());
    if (buttonResult != null) {
      debugPrint('RemoteCommandRouter: ButtonActivateIntent handled');
      return;
    }

    debugPrint('RemoteCommandRouter: No activate handler found for focused element');
  }

  /// Handle back navigation
  void _handleBack() {
    debugPrint('RemoteCommandRouter: Handling back');

    // Try using the navigator key if set
    if (_navigatorKey?.currentState != null) {
      if (_navigatorKey!.currentState!.canPop()) {
        _navigatorKey!.currentState!.pop();
        debugPrint('RemoteCommandRouter: Popped via navigator key');
        return;
      }
    }

    // Fallback: Simulate system back button press
    // This triggers the PopScope/WillPopScope handlers
    SystemNavigator.pop();
    debugPrint('RemoteCommandRouter: Called SystemNavigator.pop()');
  }

  /// Map command to LogicalKeyboardKey for reference
  LogicalKeyboardKey? commandToKey(String action, String command) {
    if (action == RemoteAction.navigate) {
      switch (command) {
        case NavigateCommand.up:
          return LogicalKeyboardKey.arrowUp;
        case NavigateCommand.down:
          return LogicalKeyboardKey.arrowDown;
        case NavigateCommand.left:
          return LogicalKeyboardKey.arrowLeft;
        case NavigateCommand.right:
          return LogicalKeyboardKey.arrowRight;
        case NavigateCommand.select:
          return LogicalKeyboardKey.select;
        case NavigateCommand.back:
          return LogicalKeyboardKey.goBack;
      }
    } else if (action == RemoteAction.media) {
      switch (command) {
        case MediaCommand.playPause:
          return LogicalKeyboardKey.mediaPlayPause;
        case MediaCommand.seekForward:
          return LogicalKeyboardKey.arrowRight;
        case MediaCommand.seekBackward:
          return LogicalKeyboardKey.arrowLeft;
      }
    }
    return null;
  }
}
