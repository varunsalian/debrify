import 'dart:async';
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
import '../../services/community/magnet_yaml_service.dart';
import '../../services/debrify_tv_zip_importer.dart';
import '../../services/debrify_tv_repository.dart';
import '../../services/debrify_tv_cache_service.dart';
import '../../models/debrify_tv_cache.dart';
import '../../models/debrify_tv_channel_record.dart';
import '../../models/indexer_manager_config.dart';
import '../../models/webdav_item.dart';

/// Callback type for remote command handlers
typedef RemoteCommandCallback =
    void Function(String action, String command, String? data);

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

  // Chunk reassembly buffer for large channel transfers
  final Map<String, _ChunkBuffer> _chunkBuffers = {};

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
    // Suppress per-chunk logs to avoid flooding
    final isChunk = command == ConfigCommand.debrifyChannelChunk;
    if (!isChunk) {
      debugPrint(
        'RemoteCommandRouter: Dispatching $action:$command${data != null ? ' with data' : ''} to ${_handlers.length} handlers',
      );
    }

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
          await _channel.invokeMethod('injectKeyEvent', {
            'keyCode': 67,
          }); // KEYCODE_DEL
          debugPrint('RemoteCommandRouter: Injected backspace');
          break;
        case TextCommand.clear:
          // Select all (Ctrl+A) then delete
          await _channel.invokeMethod('injectText', {
            'text': '',
            'clear': true,
          });
          debugPrint('RemoteCommandRouter: Cleared text field');
          break;
        case TextCommand.enter:
          // Send KEYCODE_ENTER (66) - same as keyboard's Done/Enter button
          await _channel.invokeMethod('injectKeyEvent', {'keyCode': 66});
          debugPrint('RemoteCommandRouter: Injected enter key');
          break;
      }
    } catch (e) {
      debugPrint('RemoteCommandRouter: Failed to handle text command: $e');
    }
  }

  /// Handle config commands on TV (credentials/setup from phone)
  Future<void> _handleConfigCommand(String command, String? data) async {
    if (command != ConfigCommand.debrifyChannelChunk) {
      debugPrint('RemoteCommandRouter: Handling config command: $command');
    }

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
      case ConfigCommand.trakt:
        await _handleTraktConfig(data);
        break;
      case ConfigCommand.searchEngines:
        await _handleSearchEnginesConfig(data);
        break;
      case ConfigCommand.webDav:
        await _handleWebDavConfig(data);
        break;
      case ConfigCommand.indexerManagers:
        await _handleIndexerManagersConfig(data);
        break;
      case ConfigCommand.debrifyChannel:
        await _handleDebrifyChannelConfig(data);
        break;
      case ConfigCommand.debrifyChannelStart:
        _handleDebrifyChannelStart(data);
        break;
      case ConfigCommand.debrifyChannelChunk:
        await _handleDebrifyChannelChunk(data);
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

  /// Handle Trakt session config - copies access/refresh tokens, expiry, and
  /// username from the sender so the TV ends up logged in to the same account.
  Future<void> _handleTraktConfig(String jsonData) async {
    try {
      debugPrint('RemoteCommandRouter: Configuring Trakt session...');

      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      final expiry = data['expiry_ms'] as int?;
      final username = data['username'] as String?;

      if (accessToken == null ||
          accessToken.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        _showSnackBar('Trakt: Invalid session data', isError: true);
        return;
      }

      await StorageService.setTraktAccessToken(accessToken);
      await StorageService.setTraktRefreshToken(refreshToken);
      if (expiry != null) {
        await StorageService.setTraktTokenExpiry(expiry);
      }
      if (username != null && username.isNotEmpty) {
        await StorageService.setTraktUsername(username);
      }

      debugPrint('RemoteCommandRouter: Trakt session configured successfully');
      _showSnackBar('Trakt connected successfully');
    } catch (e) {
      debugPrint('RemoteCommandRouter: Failed to configure Trakt: $e');
      _showSnackBar('Trakt: Configuration failed', isError: true);
    }
  }

  /// Handle config complete signal.
  ///
  /// If this device is still in first-time onboarding, mark it complete and
  /// restart the app flow so the new credentials/integrations are picked up
  /// (the original "set up TV from phone" flow).
  ///
  /// If onboarding is already done — e.g. a phone or already-configured TV
  /// is in receive mode mid-session — we just acknowledge with a snackbar
  /// and let the user keep using the app uninterrupted.
  Future<void> _handleConfigComplete() async {
    final wasOnboarding = !(await StorageService.isInitialSetupComplete());

    if (!wasOnboarding) {
      debugPrint('RemoteCommandRouter: Config complete (already onboarded)');
      _showSnackBar('Setup received');
      return;
    }

    debugPrint(
      'RemoteCommandRouter: Config complete during onboarding, restarting app flow...',
    );

    await StorageService.setInitialSetupComplete(true);
    _showSnackBar('Setup received! Restarting...');

    // Give snackbar time to show, then restart app
    await Future.delayed(const Duration(milliseconds: 1500));

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
        final engineInfo = availableEngines
            .where((e) => e.id == engineId)
            .firstOrNull;
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
          final yamlContent = await remoteManager.downloadEngineYaml(
            engineInfo.fileName,
          );
          if (yamlContent == null) {
            debugPrint(
              'RemoteCommandRouter: Failed to download engine $engineId',
            );
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
          debugPrint(
            'RemoteCommandRouter: Failed to import engine $engineId: $e',
          );
          failCount++;
        }
      }

      if (failCount == 0) {
        _showSnackBar(
          '$successCount search engine${successCount != 1 ? 's' : ''} configured',
        );
      } else if (successCount == 0) {
        _showSnackBar('Search engines: All failed to import', isError: true);
      } else {
        _showSnackBar(
          'Search engines: $successCount imported, $failCount failed',
          isError: true,
        );
      }
    } catch (e) {
      debugPrint('RemoteCommandRouter: Failed to configure search engines: $e');
      _showSnackBar('Search engines: Configuration failed', isError: true);
    }
  }

  /// Handle WebDAV servers config — merges incoming entries into the local
  /// list, de-duped by normalized base URL.
  Future<void> _handleWebDavConfig(String jsonData) async {
    try {
      debugPrint('RemoteCommandRouter: Configuring WebDAV servers...');

      final decoded = jsonDecode(jsonData);
      if (decoded is! List) {
        _showSnackBar('WebDAV: Invalid payload', isError: true);
        return;
      }

      String normalize(String url) =>
          url.trim().toLowerCase().replaceFirst(RegExp(r'/+$'), '');

      final existing = await StorageService.getWebDavServers();
      final existingKeys = <String>{
        for (final s in existing) normalize(s.baseUrl),
      };
      final merged = List<WebDavConfig>.from(existing);
      int imported = 0;
      int skipped = 0;
      for (final raw in decoded) {
        if (raw is! Map) {
          skipped++;
          continue;
        }
        try {
          final config = WebDavConfig.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (config.baseUrl.trim().isEmpty) {
            skipped++;
            continue;
          }
          final key = normalize(config.baseUrl);
          if (existingKeys.contains(key)) {
            skipped++;
            continue;
          }
          merged.add(config);
          existingKeys.add(key);
          imported++;
        } catch (e) {
          debugPrint('RemoteCommandRouter: WebDAV entry failed: $e');
          skipped++;
        }
      }

      if (imported > 0) {
        await StorageService.saveWebDavServers(merged);
      }

      if (imported > 0 && skipped == 0) {
        _showSnackBar(
          '$imported WebDAV server${imported == 1 ? '' : 's'} configured',
        );
      } else if (imported > 0) {
        _showSnackBar(
          'WebDAV: $imported added, $skipped already present or invalid',
        );
      } else if (skipped > 0) {
        _showSnackBar('WebDAV: nothing new to add');
      } else {
        _showSnackBar('WebDAV: empty payload', isError: true);
      }
    } catch (e) {
      debugPrint('RemoteCommandRouter: Failed to configure WebDAV: $e');
      _showSnackBar('WebDAV: Configuration failed', isError: true);
    }
  }

  /// Handle indexer manager (Jackett / Prowlarr) configs — merges incoming
  /// entries into the local list, de-duped by (type, normalized baseUrl).
  Future<void> _handleIndexerManagersConfig(String jsonData) async {
    try {
      debugPrint('RemoteCommandRouter: Configuring indexer managers...');

      final decoded = jsonDecode(jsonData);
      if (decoded is! List) {
        _showSnackBar('Indexer managers: Invalid payload', isError: true);
        return;
      }

      String normalize(String url) =>
          url.trim().toLowerCase().replaceFirst(RegExp(r'/+$'), '');
      String fingerprint(IndexerManagerConfig c) =>
          '${c.type.value}|${normalize(c.baseUrl)}';

      final existing = await StorageService.getIndexerManagerConfigs();
      final existingKeys = <String>{
        for (final c in existing) fingerprint(c),
      };
      final merged = List<IndexerManagerConfig>.from(existing);
      int imported = 0;
      int skipped = 0;
      for (final raw in decoded) {
        if (raw is! Map) {
          skipped++;
          continue;
        }
        try {
          final config = IndexerManagerConfig.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (config.baseUrl.trim().isEmpty ||
              config.apiKey.trim().isEmpty) {
            skipped++;
            continue;
          }
          final key = fingerprint(config);
          if (existingKeys.contains(key)) {
            skipped++;
            continue;
          }
          merged.add(config);
          existingKeys.add(key);
          imported++;
        } catch (e) {
          debugPrint(
            'RemoteCommandRouter: indexer manager entry failed: $e',
          );
          skipped++;
        }
      }

      if (imported > 0) {
        await StorageService.setIndexerManagerConfigs(merged);
      }

      if (imported > 0 && skipped == 0) {
        _showSnackBar(
          '$imported indexer manager${imported == 1 ? '' : 's'} configured',
        );
      } else if (imported > 0) {
        _showSnackBar(
          'Indexer managers: $imported added, $skipped already present or invalid',
        );
      } else if (skipped > 0) {
        _showSnackBar('Indexer managers: nothing new to add');
      } else {
        _showSnackBar('Indexer managers: empty payload', isError: true);
      }
    } catch (e) {
      debugPrint(
        'RemoteCommandRouter: Failed to configure indexer managers: $e',
      );
      _showSnackBar('Indexer managers: Configuration failed', isError: true);
    }
  }

  /// Handle Debrify TV channel import from remote
  Future<void> _handleDebrifyChannelConfig(String debrifyUri) async {
    try {
      debugPrint('RemoteCommandRouter: Importing Debrify TV channel...');

      // 1. Decode the debrify:// URI
      final decoded = MagnetYamlService.decode(debrifyUri);

      // 2. Parse YAML into channel data
      final parsed = DebrifyTvZipImporter.parseYaml(
        sourceName: decoded.channelName,
        content: decoded.yamlContent,
      );

      // 3. Reuse existing channelId if a channel with the same name exists
      final existingChannels = await DebrifyTvRepository.instance
          .fetchAllChannels();
      final existingMatch = existingChannels
          .where(
            (c) => c.name.toLowerCase() == parsed.channelName.toLowerCase(),
          )
          .firstOrNull;
      final channelId =
          existingMatch?.channelId ??
          DateTime.now().microsecondsSinceEpoch.toString();
      final now = DateTime.now();

      final record = DebrifyTvChannelRecord(
        channelId: channelId,
        name: parsed.channelName,
        keywords: parsed.displayKeywords,
        avoidNsfw: parsed.avoidNsfw,
        channelNumber: 0,
        createdAt: now,
        updatedAt: now,
      );

      final entry = DebrifyTvChannelCacheEntry(
        version: 1,
        channelId: channelId,
        normalizedKeywords: parsed.normalizedKeywords,
        fetchedAt: now.millisecondsSinceEpoch,
        status: DebrifyTvCacheStatus.ready,
        errorMessage: null,
        torrents: parsed.torrents,
        keywordStats: parsed.keywordStats,
      );

      await DebrifyTvRepository.instance.upsertChannel(record);
      await DebrifyTvCacheService.saveEntry(entry);

      debugPrint(
        'RemoteCommandRouter: Channel imported: ${parsed.channelName}',
      );
      _showSnackBar('Channel imported: ${parsed.channelName}');
    } catch (e) {
      debugPrint('RemoteCommandRouter: Failed to import channel: $e');
      _showSnackBar('Failed to import channel', isError: true);
    }
  }

  /// Handle start of a chunked channel transfer
  void _handleDebrifyChannelStart(String jsonData) {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final transferId = data['transferId'] as String;
      final channelName = data['channelName'] as String;
      final totalChunks = data['totalChunks'] as int;

      debugPrint(
        'RemoteCommandRouter: Chunked transfer started: '
        '$channelName ($totalChunks chunks)',
      );

      // Clean up any stale buffer with the same ID
      _chunkBuffers[transferId]?.timeout?.cancel();

      _chunkBuffers[transferId] = _ChunkBuffer(
        channelName: channelName,
        totalChunks: totalChunks,
        chunks: List<String?>.filled(totalChunks, null),
        timeout: Timer(kChunkTransferTimeout, () {
          debugPrint(
            'RemoteCommandRouter: Chunk transfer timed out: $transferId',
          );
          _chunkBuffers.remove(transferId);
          _showSnackBar(
            'Channel transfer timed out: $channelName',
            isError: true,
          );
        }),
      );
    } catch (e) {
      debugPrint('RemoteCommandRouter: Failed to parse chunk start: $e');
      _showSnackBar('Failed to receive channel transfer', isError: true);
    }
  }

  /// Handle a single chunk of a chunked channel transfer
  Future<void> _handleDebrifyChannelChunk(String jsonData) async {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final transferId = data['transferId'] as String;
      final index = data['index'] as int;
      final chunkData = data['data'] as String;

      final buffer = _chunkBuffers[transferId];
      if (buffer == null) {
        debugPrint(
          'RemoteCommandRouter: No buffer for transfer $transferId '
          '(timed out or never started)',
        );
        return;
      }

      // Only count if this slot was not already filled (guards against duplicate UDP packets)
      if (buffer.chunks[index] == null) {
        buffer.receivedCount++;
      }
      buffer.chunks[index] = chunkData;

      // Check if all chunks have arrived
      if (buffer.receivedCount >= buffer.totalChunks) {
        buffer.timeout?.cancel();
        _chunkBuffers.remove(transferId);

        // Reassemble: base64-decode each chunk, concatenate bytes, then UTF-8 decode
        final byteChunks = <List<int>>[];
        for (final chunk in buffer.chunks) {
          byteChunks.add(base64.decode(chunk!));
        }
        final allBytes = byteChunks.expand((b) => b).toList();
        final fullUri = utf8.decode(allBytes);

        debugPrint(
          'RemoteCommandRouter: All chunks received for ${buffer.channelName}, '
          'reassembled ${fullUri.length} chars',
        );

        // Process through the normal handler
        await _handleDebrifyChannelConfig(fullUri);
      }
    } catch (e) {
      debugPrint('RemoteCommandRouter: Failed to handle chunk: $e');
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
      debugPrint(
        'RemoteCommandRouter: No key code mapping for $action:$command',
      );
      return;
    }

    try {
      await _channel.invokeMethod('injectKeyEvent', {'keyCode': keyCode});
      debugPrint(
        'RemoteCommandRouter: Injected key event $keyCode for $action:$command',
      );
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
    final buttonResult = Actions.maybeInvoke<Intent>(
      context,
      const ButtonActivateIntent(),
    );
    if (buttonResult != null) {
      debugPrint('RemoteCommandRouter: ButtonActivateIntent handled');
      return;
    }

    debugPrint(
      'RemoteCommandRouter: No activate handler found for focused element',
    );
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

/// Buffer for reassembling chunked channel transfers
class _ChunkBuffer {
  final String channelName;
  final int totalChunks;
  final List<String?> chunks;
  final Timer? timeout;
  int receivedCount = 0;

  _ChunkBuffer({
    required this.channelName,
    required this.totalChunks,
    required this.chunks,
    required this.timeout,
  });
}
