import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/storage_service.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../services/iptv_transfer_payload.dart';
import '../../services/stream_badges_service.dart';
import '../../services/remote_control/remote_chunked_send.dart';
import '../../services/remote_control/remote_control_state.dart';
import 'remote_pairing_dialog.dart';
import '../../services/remote_control/remote_constants.dart';
import '../../services/engine/local_engine_storage.dart';
import '../../services/profiles/profile_async_authorization.dart';
import '../../models/profiles/profile_policy.dart';

/// Widget for exporting setup/credentials to TV
class RemoteConfigExport extends StatefulWidget {
  final VoidCallback onBack;

  const RemoteConfigExport({super.key, required this.onBack});

  @override
  State<RemoteConfigExport> createState() => _RemoteConfigExportState();
}

class _ConfigItem {
  final String id;
  final String name;
  final String icon;
  final bool isConfigured;
  bool selected;

  _ConfigItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.isConfigured,
    this.selected = false,
  });
}

class _RemoteConfigExportState extends State<RemoteConfigExport> {
  bool _loading = true;
  bool _sending = false;

  // Config items
  _ConfigItem? _realDebrid;
  _ConfigItem? _torbox;
  _ConfigItem? _premiumize;
  _ConfigItem? _allDebrid;
  _ConfigItem? _pikpak;
  _ConfigItem? _trakt;
  _ConfigItem? _simkl;
  _ConfigItem? _mdblist;
  _ConfigItem? _trackingPreferences;
  _ConfigItem? _searchEngines;
  _ConfigItem? _webDav;
  _ConfigItem? _indexerManagers;
  _ConfigItem? _iptvPlaylists;
  _ConfigItem? _iptvFavorites;
  _ConfigItem? _iptvLists;
  _ConfigItem? _streamBadges;

  // Non-secret account labels used only for the transfer inventory.
  String? _traktUsername;
  String? _simklUsername;
  String? _mdblistUsername;

  // PikPak password (entered by user)
  final _pikpakPasswordController = TextEditingController();
  bool _showPikpakPassword = false;

  // Inventory state intentionally retains counts, not decrypted transfer
  // payloads. Every selected item is re-read and re-authorized at send time.
  int _engineCount = 0;
  int _webDavCount = 0;
  int _indexerManagerCount = 0;
  int _iptvPlaylistCount = 0;
  int _iptvFavoriteCount = 0;
  int _iptvListCount = 0;
  int _iptvListChannelCount = 0;
  int _streamBadgeCount = 0;

  /// Playlists imported from a file, which can't be sent — their definition
  /// is the raw M3U text. Surfaced so the screen says so instead of quietly
  /// sending fewer providers than the user has.
  int _iptvFileImported = 0;

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  @override
  void dispose() {
    _pikpakPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadConfigs() async {
    setState(() => _loading = true);

    try {
      // Load Real-Debrid
      final realDebridApiKey = await StorageService.getApiKey(
        forRemoteTransfer: true,
      );
      final rdEnabled = await StorageService.getRealDebridIntegrationEnabled();
      final hasRd =
          realDebridApiKey != null && realDebridApiKey.isNotEmpty && rdEnabled;

      // Load Torbox
      final torboxApiKey = await StorageService.getTorboxApiKey(
        forRemoteTransfer: true,
      );
      final tbEnabled = await StorageService.getTorboxIntegrationEnabled();
      final hasTb =
          torboxApiKey != null && torboxApiKey.isNotEmpty && tbEnabled;

      // Load Premiumize
      final premiumizeApiKey = await StorageService.getPremiumizeApiKey(
        forRemoteTransfer: true,
      );
      final pmEnabled = await StorageService.getPremiumizeIntegrationEnabled();
      final hasPm =
          premiumizeApiKey != null && premiumizeApiKey.isNotEmpty && pmEnabled;

      // Load AllDebrid
      final allDebridApiKey = await StorageService.getAllDebridApiKey(
        forRemoteTransfer: true,
      );
      final adEnabled = await StorageService.getAllDebridIntegrationEnabled();
      final hasAd =
          allDebridApiKey != null && allDebridApiKey.isNotEmpty && adEnabled;

      // Load PikPak
      final pikpakEmail = await StorageService.getPikPakEmail(
        forRemoteTransfer: true,
      );
      final ppEnabled = await StorageService.getPikPakEnabled();
      final hasPp = pikpakEmail != null && pikpakEmail.isNotEmpty && ppEnabled;

      // Load Trakt session
      final traktAccessToken = await StorageService.getTraktAccessToken(
        forRemoteTransfer: true,
      );
      final traktRefreshToken = await StorageService.getTraktRefreshToken(
        forRemoteTransfer: true,
      );
      _traktUsername = await StorageService.getTraktUsername();
      final hasTrakt =
          traktAccessToken != null &&
          traktAccessToken.isNotEmpty &&
          traktRefreshToken != null &&
          traktRefreshToken.isNotEmpty;

      // Load Simkl session
      final simklAccessToken = await StorageService.getSimklAccessToken(
        forRemoteTransfer: true,
      );
      _simklUsername = await StorageService.getSimklUsername();
      final hasSimkl = simklAccessToken != null && simklAccessToken.isNotEmpty;

      final mdblistApiKey = kMdblistEnabled
          ? await StorageService.getMdblistApiKey(forRemoteTransfer: true)
          : null;
      _mdblistUsername = await StorageService.getMdblistUsername();
      final hasMdblist = mdblistApiKey?.isNotEmpty ?? false;

      // Load Search Engines
      await LocalEngineStorage.instance.initialize();
      final engineIds = await LocalEngineStorage.instance
          .getImportedEngineIds();
      _engineCount = engineIds.length;
      final hasEngines = _engineCount > 0;

      // WebDAV / indexer managers: the protocol and the TV have handled these
      // since they were added to "Transfer Everything" — this screen just
      // never offered them.
      try {
        final servers = await StorageService.getWebDavServers(
          forSettings: false,
          forRemoteTransfer: true,
        );
        _webDavCount = servers.length;
      } catch (_) {
        debugPrint('RemoteConfigExport: WebDAV inventory failed');
        _webDavCount = 0;
      }
      try {
        final managers = await StorageService.getIndexerManagerConfigs(
          forSettings: false,
          forRemoteTransfer: true,
        );
        _indexerManagerCount = managers.length;
      } catch (_) {
        debugPrint('RemoteConfigExport: indexer inventory failed');
        _indexerManagerCount = 0;
      }

      try {
        final playlists = await IptvTransferPayload.buildPlaylists(
          forRemoteTransfer: true,
        );
        final favorites = await IptvTransferPayload.buildFavorites(
          forRemoteTransfer: true,
        );
        final lists = await IptvTransferPayload.buildCustomLists(
          forRemoteTransfer: true,
        );
        _iptvPlaylistCount = playlists.length;
        _iptvFavoriteCount = favorites.length;
        _iptvListCount = lists.length;
        _iptvListChannelCount = IptvTransferPayload.countListChannels(lists);
        _iptvFileImported =
            (await IptvTransferPayload.countPlaylists()).fileImported;
      } catch (_) {
        debugPrint('RemoteConfigExport: IPTV inventory failed');
        _iptvPlaylistCount = 0;
        _iptvFavoriteCount = 0;
        _iptvListCount = 0;
        _iptvListChannelCount = 0;
      }

      try {
        _streamBadgeCount =
            (await StreamBadgesService.instance.getSources()).length;
      } catch (_) {
        debugPrint('RemoteConfigExport: stream badge inventory failed');
        _streamBadgeCount = 0;
      }

      if (!mounted) return;
      setState(() {
        _realDebrid = _ConfigItem(
          id: ConfigCommand.realDebrid,
          name: 'Real-Debrid',
          icon: 'rd',
          isConfigured: hasRd,
          selected: hasRd,
        );

        _torbox = _ConfigItem(
          id: ConfigCommand.torbox,
          name: 'Torbox',
          icon: 'tb',
          isConfigured: hasTb,
          selected: hasTb,
        );

        _premiumize = _ConfigItem(
          id: ConfigCommand.premiumize,
          name: 'Premiumize',
          icon: 'pm',
          isConfigured: hasPm,
          selected: hasPm,
        );

        _allDebrid = _ConfigItem(
          id: ConfigCommand.allDebrid,
          name: 'AllDebrid',
          icon: 'ad',
          isConfigured: hasAd,
          selected: hasAd,
        );

        _pikpak = _ConfigItem(
          id: ConfigCommand.pikpak,
          name: 'PikPak',
          icon: 'pp',
          isConfigured: hasPp,
          selected:
              false, // Default to false since password needs to be entered
        );

        _trakt = _ConfigItem(
          id: ConfigCommand.trakt,
          name: 'Trakt',
          icon: 'tk',
          isConfigured: hasTrakt,
          selected: hasTrakt,
        );

        _simkl = _ConfigItem(
          id: ConfigCommand.simkl,
          name: 'Simkl',
          icon: 'sk',
          isConfigured: hasSimkl,
          selected: hasSimkl,
        );

        _mdblist = _ConfigItem(
          id: ConfigCommand.mdblist,
          name: 'MDBList',
          icon: 'ml',
          isConfigured: hasMdblist,
          selected: hasMdblist,
        );

        _trackingPreferences = _ConfigItem(
          id: ConfigCommand.trackingPreferences,
          name: 'Tracking preferences',
          icon: 'tk',
          isConfigured: true,
          selected: true,
        );

        _searchEngines = _ConfigItem(
          id: ConfigCommand.searchEngines,
          name: 'Search Engines',
          icon: 'se',
          isConfigured: hasEngines,
          selected: hasEngines,
        );

        _webDav = _ConfigItem(
          id: ConfigCommand.webDav,
          name: 'WebDAV',
          icon: 'wd',
          isConfigured: _webDavCount > 0,
          selected: _webDavCount > 0,
        );

        _indexerManagers = _ConfigItem(
          id: ConfigCommand.indexerManagers,
          name: 'Jackett/Prowlarr',
          icon: 'im',
          isConfigured: _indexerManagerCount > 0,
          selected: _indexerManagerCount > 0,
        );

        _iptvPlaylists = _ConfigItem(
          id: ConfigCommand.iptvPlaylists,
          name: 'IPTV Providers',
          icon: 'iptv',
          isConfigured: _iptvPlaylistCount > 0,
          selected: _iptvPlaylistCount > 0,
        );

        _iptvFavorites = _ConfigItem(
          id: ConfigCommand.iptvFavorites,
          name: 'IPTV Favorites',
          icon: 'fav',
          isConfigured: _iptvFavoriteCount > 0,
          selected: _iptvFavoriteCount > 0,
        );

        _iptvLists = _ConfigItem(
          id: ConfigCommand.iptvLists,
          name: 'IPTV Lists',
          icon: 'list',
          isConfigured: _iptvListCount > 0,
          selected: _iptvListCount > 0,
        );

        _streamBadges = _ConfigItem(
          id: ConfigCommand.streamBadges,
          name: 'Stream Badges',
          icon: 'badges',
          isConfigured: _streamBadgeCount > 0,
          selected: _streamBadgeCount > 0,
        );

        _loading = false;
      });
    } catch (_) {
      debugPrint('RemoteConfigExport: setup inventory failed');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Every tile this screen can show, in send order — providers before the
  /// memberships that name them.
  List<_ConfigItem> get _allItems => [
    for (final item in [
      _realDebrid,
      _torbox,
      _premiumize,
      _allDebrid,
      _pikpak,
      _trakt,
      _simkl,
      _mdblist,
      _trackingPreferences,
      _searchEngines,
      _webDav,
      _indexerManagers,
      _iptvPlaylists,
      _iptvFavorites,
      _iptvLists,
      _streamBadges,
    ])
      if (item != null) item,
  ];

  /// File-imported playlists aren't sendable, but a user whose only IPTV setup
  /// is file-based must still be told why nothing about it is on offer —
  /// otherwise the screen claims they have nothing configured at all.
  bool get _hasAnyConfigured =>
      _allItems.any((i) => i.isConfigured) || _iptvFileImported > 0;

  bool get _hasAnySelected => _allItems.any((i) => i.selected);

  bool get _isPikpakPasswordValid {
    if (_pikpak?.selected != true) return true;
    return _pikpakPasswordController.text.isNotEmpty;
  }

  Future<void> _sendToTv() async {
    if (!_hasAnySelected || !_isPikpakPasswordValid) return;

    final connectedDevice = RemoteControlState().connectedDevice;
    if (connectedDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No TV connected'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Credential gate: encrypted session + pairing code (or remembered
    // pairing). Old-version TVs are refused with an "update the TV" dialog.
    final session = await ensureAuthorizedSession(
      context,
      RemoteControlState(),
      connectedDevice,
    );
    if (session == null || !mounted) return;

    setState(() => _sending = true);
    HapticFeedback.mediumImpact();

    final targetIp = connectedDevice.ip;
    final state = RemoteControlState();
    final supportsApplicationResult =
        connectedDevice.supportsRemoteTransferResult;
    final requestId = createRemoteTransferRequestId();
    final applicationResult = Completer<({bool ok, String message})>();
    StreamSubscription<({String requestId, bool ok, String message})>?
    resultSubscription;
    if (supportsApplicationResult) {
      resultSubscription = state.remoteTransferResults.stream.listen((result) {
        if (result.requestId == requestId && !applicationResult.isCompleted) {
          applicationResult.complete((ok: result.ok, message: result.message));
        }
      });
    }
    int successCount = 0;
    int failCount = 0;
    final List<String> results = [];
    final List<String> deliveredCommands = [];
    String transferData(String value) => supportsApplicationResult
        ? remoteTransferItemBody(requestId: requestId, payload: value)
        : value;

    try {
      if (supportsApplicationResult &&
          !await beginRemoteTransfer(state, targetIp, requestId: requestId)) {
        throw StateError('The TV refused to start the configuration transfer');
      }

      Future<void> sendSelected(
        bool selected,
        String label,
        String command,
        Future<bool> Function() send,
      ) async {
        if (!selected) return;
        final authorization = await ProfileAsyncAuthorization.capture(
          ProfileFeature.remoteTransfer,
        );
        final sent = authorization == null
            ? await send()
            : await authorization.runIfCurrentAsOutbound(send);
        if (sent) {
          successCount++;
          results.add(label);
          deliveredCommands.add(command);
        } else {
          failCount++;
        }
      }

      Future<bool> sendScalar(
        String command,
        Future<String?> Function() read,
      ) async {
        final value = await read();
        return value != null &&
            value.isNotEmpty &&
            await state.sendConfigCommandToDevice(
              command,
              targetIp,
              configData: transferData(value),
            );
      }

      await sendSelected(
        _realDebrid?.selected == true,
        'Real-Debrid',
        ConfigCommand.realDebrid,
        () => sendScalar(
          ConfigCommand.realDebrid,
          () => StorageService.getApiKey(forRemoteTransfer: true),
        ),
      );
      await sendSelected(
        _torbox?.selected == true,
        'Torbox',
        ConfigCommand.torbox,
        () => sendScalar(
          ConfigCommand.torbox,
          () => StorageService.getTorboxApiKey(forRemoteTransfer: true),
        ),
      );
      await sendSelected(
        _premiumize?.selected == true,
        'Premiumize',
        ConfigCommand.premiumize,
        () => sendScalar(
          ConfigCommand.premiumize,
          () => StorageService.getPremiumizeApiKey(forRemoteTransfer: true),
        ),
      );
      await sendSelected(
        _allDebrid?.selected == true,
        'AllDebrid',
        ConfigCommand.allDebrid,
        () => sendScalar(
          ConfigCommand.allDebrid,
          () => StorageService.getAllDebridApiKey(forRemoteTransfer: true),
        ),
      );
      await sendSelected(
        _pikpak?.selected == true,
        'PikPak',
        ConfigCommand.pikpak,
        () async {
          final email = await StorageService.getPikPakEmail(
            forRemoteTransfer: true,
          );
          if (email == null || email.isEmpty) return false;
          return state.sendConfigCommandToDevice(
            ConfigCommand.pikpak,
            targetIp,
            configData: transferData(
              jsonEncode(<String, Object?>{
                'email': email,
                'password': _pikpakPasswordController.text,
              }),
            ),
          );
        },
      );
      await sendSelected(
        _trakt?.selected == true,
        'Trakt',
        ConfigCommand.trakt,
        () async {
          final access = await StorageService.getTraktAccessToken(
            forRemoteTransfer: true,
          );
          final refresh = await StorageService.getTraktRefreshToken(
            forRemoteTransfer: true,
          );
          if (access == null ||
              access.isEmpty ||
              refresh == null ||
              refresh.isEmpty) {
            return false;
          }
          final expiry = await StorageService.getTraktTokenExpiry();
          final username = await StorageService.getTraktUsername();
          return state.sendConfigCommandToDevice(
            ConfigCommand.trakt,
            targetIp,
            configData: transferData(
              jsonEncode(<String, Object?>{
                'access_token': access,
                'refresh_token': refresh,
                if (expiry != null) 'expiry_ms': expiry,
                if (username != null) 'username': username,
              }),
            ),
          );
        },
      );
      await sendSelected(
        _simkl?.selected == true,
        'Simkl',
        ConfigCommand.simkl,
        () async {
          final access = await StorageService.getSimklAccessToken(
            forRemoteTransfer: true,
          );
          if (access == null || access.isEmpty) return false;
          final username = await StorageService.getSimklUsername();
          return state.sendConfigCommandToDevice(
            ConfigCommand.simkl,
            targetIp,
            configData: transferData(
              jsonEncode(<String, Object?>{
                'access_token': access,
                if (username != null) 'username': username,
              }),
            ),
          );
        },
      );
      await sendSelected(
        _mdblist?.selected == true,
        'MDBList',
        ConfigCommand.mdblist,
        () async {
          final apiKey = await StorageService.getMdblistApiKey(
            forRemoteTransfer: true,
          );
          if (apiKey == null || apiKey.isEmpty) return false;
          final username = await StorageService.getMdblistUsername();
          return state.sendConfigCommandToDevice(
            ConfigCommand.mdblist,
            targetIp,
            configData: transferData(
              jsonEncode(<String, Object?>{
                'api_key': apiKey,
                if (username != null) 'username': username,
              }),
            ),
          );
        },
      );
      await sendSelected(
        _trackingPreferences?.selected == true,
        'Tracking preferences',
        ConfigCommand.trackingPreferences,
        () async => state.sendConfigCommandToDevice(
          ConfigCommand.trackingPreferences,
          targetIp,
          configData: transferData(
            jsonEncode(await StorageService.buildTrackingPreferencesPayload()),
          ),
        ),
      );
      await sendSelected(
        _searchEngines?.selected == true,
        'Search Engines',
        ConfigCommand.searchEngines,
        () async {
          await LocalEngineStorage.instance.initialize();
          final engineIds = await LocalEngineStorage.instance
              .getImportedEngineIds();
          return engineIds.isNotEmpty &&
              await state.sendConfigCommandToDevice(
                ConfigCommand.searchEngines,
                targetIp,
                configData: transferData(jsonEncode(engineIds)),
              );
        },
      );
      await sendSelected(
        _webDav?.selected == true,
        'WebDAV',
        ConfigCommand.webDav,
        () async {
          final servers = await StorageService.getWebDavServers(
            forSettings: false,
            forRemoteTransfer: true,
          );
          if (servers.isEmpty) return false;
          return state.sendConfigCommandToDevice(
            ConfigCommand.webDav,
            targetIp,
            configData: transferData(
              jsonEncode([
                for (final server in servers) server.toTransferJson(),
              ]),
            ),
          );
        },
      );
      await sendSelected(
        _indexerManagers?.selected == true,
        'Jackett/Prowlarr',
        ConfigCommand.indexerManagers,
        () async {
          final managers = await StorageService.getIndexerManagerConfigs(
            forSettings: false,
            forRemoteTransfer: true,
          );
          if (managers.isEmpty) return false;
          return state.sendConfigCommandToDevice(
            ConfigCommand.indexerManagers,
            targetIp,
            configData: transferData(
              jsonEncode([
                for (final manager in managers) manager.toTransferJson(),
              ]),
            ),
          );
        },
      );
      await sendSelected(
        _iptvPlaylists?.selected == true,
        'IPTV Providers',
        ConfigCommand.iptvPlaylists,
        () async {
          final payload = await IptvTransferPayload.buildPlaylists(
            forRemoteTransfer: true,
          );
          return payload.isNotEmpty &&
              await sendConfigPayloadToDevice(
                state,
                ConfigCommand.iptvPlaylists,
                targetIp,
                jsonEncode(payload),
                label: 'IPTV providers',
                transferRequestId: supportsApplicationResult ? requestId : null,
              );
        },
      );
      await sendSelected(
        _iptvFavorites?.selected == true,
        'IPTV Favorites',
        ConfigCommand.iptvFavorites,
        () async {
          final payload = await IptvTransferPayload.buildFavorites(
            forRemoteTransfer: true,
          );
          return payload.isNotEmpty &&
              await sendConfigPayloadToDevice(
                state,
                ConfigCommand.iptvFavorites,
                targetIp,
                jsonEncode(payload),
                label: 'IPTV favorites',
                transferRequestId: supportsApplicationResult ? requestId : null,
              );
        },
      );
      await sendSelected(
        _iptvLists?.selected == true,
        'IPTV Lists',
        ConfigCommand.iptvLists,
        () async {
          final payload = await IptvTransferPayload.buildCustomLists(
            forRemoteTransfer: true,
          );
          return payload.isNotEmpty &&
              await sendConfigPayloadToDevice(
                state,
                ConfigCommand.iptvLists,
                targetIp,
                jsonEncode(payload),
                label: 'IPTV lists',
                transferRequestId: supportsApplicationResult ? requestId : null,
              );
        },
      );
      await sendSelected(
        _streamBadges?.selected == true,
        'Stream Badges',
        ConfigCommand.streamBadges,
        () async {
          final payload = await StreamBadgesService.instance.exportJson();
          return payload.isNotEmpty &&
              await sendConfigPayloadToDevice(
                state,
                ConfigCommand.streamBadges,
                targetIp,
                jsonEncode(payload),
                label: 'Stream badges',
                transferRequestId: supportsApplicationResult ? requestId : null,
              );
        },
      );

      // Send complete signal to trigger TV restart (only if at least one succeeded)
      if (successCount > 0) {
        // Small delay to ensure previous commands are processed
        await Future.delayed(const Duration(milliseconds: 500));
        final completed = supportsApplicationResult
            ? await sendRemoteTransferCompletion(
                state,
                targetIp,
                requestId: requestId,
                expectedCommands: deliveredCommands,
              )
            : await state.sendConfigCommandToDevice(
                ConfigCommand.complete,
                targetIp,
              );
        if (!completed) {
          throw StateError('Remote configuration completion was refused');
        }
        if (supportsApplicationResult) {
          final result = await applicationResult.future.timeout(
            const Duration(minutes: 3),
            onTimeout: () =>
                (ok: false, message: 'No application result received from TV'),
          );
          if (!result.ok) throw StateError(result.message);
        }
      }

      // Show result
      if (mounted) {
        if (failCount == 0 && successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                supportsApplicationResult
                    ? 'Applied ${results.join(", ")} on TV'
                    : 'Delivered ${results.join(", ")} — confirm on TV',
              ),
              backgroundColor: supportsApplicationResult
                  ? const Color(0xFF10B981)
                  : const Color(0xFFF59E0B),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        } else if (successCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send configuration'),
              backgroundColor: Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${supportsApplicationResult ? 'Applied' : 'Delivered'} '
                '${results.join(", ")}, but some failed',
              ),
              backgroundColor: const Color(0xFFF59E0B),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (_) {
      debugPrint('RemoteConfigExport: setup send failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send configuration'),
            backgroundColor: Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      await resultSubscription?.cancel();
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back to menu button
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back to menu'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.7),
          ),
        ),

        const SizedBox(height: 16),

        // Title
        const Text(
          'Send Setup to TV',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),

        const SizedBox(height: 8),

        Text(
          'Select services to send to your TV',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),

        const SizedBox(height: 24),

        // Content
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            ),
          )
        else if (!_hasAnyConfigured)
          _buildEmptyState()
        else ...[
          // Debrid providers section
          if (_realDebrid?.isConfigured == true ||
              _torbox?.isConfigured == true ||
              _premiumize?.isConfigured == true ||
              _allDebrid?.isConfigured == true) ...[
            _buildSectionHeader('DEBRID PROVIDERS'),
            const SizedBox(height: 8),
            if (_realDebrid?.isConfigured == true)
              _buildConfigTile(_realDebrid!),
            if (_torbox?.isConfigured == true) _buildConfigTile(_torbox!),
            if (_premiumize?.isConfigured == true)
              _buildConfigTile(_premiumize!),
            if (_allDebrid?.isConfigured == true) _buildConfigTile(_allDebrid!),
            const SizedBox(height: 16),
          ],

          // PikPak section
          if (_pikpak?.isConfigured == true) ...[
            _buildSectionHeader('CLOUD STORAGE'),
            const SizedBox(height: 8),
            _buildPikPakTile(),
            const SizedBox(height: 16),
          ],

          // Trakt / Simkl section
          if (_trakt?.isConfigured == true ||
              _simkl?.isConfigured == true ||
              _mdblist?.isConfigured == true) ...[
            _buildSectionHeader('TRACKING'),
            const SizedBox(height: 8),
            if (_trakt?.isConfigured == true)
              _buildConfigTile(
                _trakt!,
                subtitle: _traktUsername ?? 'Signed in',
              ),
            if (_simkl?.isConfigured == true)
              _buildConfigTile(
                _simkl!,
                subtitle: _simklUsername ?? 'Signed in',
              ),
            if (_mdblist?.isConfigured == true)
              _buildConfigTile(
                _mdblist!,
                subtitle: _mdblistUsername ?? 'Signed in',
              ),
            const SizedBox(height: 16),
          ],

          // Search engines section
          if (_searchEngines?.isConfigured == true ||
              _indexerManagers?.isConfigured == true) ...[
            _buildSectionHeader('SEARCH'),
            const SizedBox(height: 8),
            if (_searchEngines?.isConfigured == true)
              _buildConfigTile(
                _searchEngines!,
                subtitle: '$_engineCount engine${_engineCount != 1 ? 's' : ''}',
              ),
            if (_indexerManagers?.isConfigured == true)
              _buildConfigTile(
                _indexerManagers!,
                subtitle:
                    '$_indexerManagerCount '
                    'manager${_indexerManagerCount != 1 ? 's' : ''}',
              ),
            const SizedBox(height: 16),
          ],

          // WebDAV section
          if (_webDav?.isConfigured == true) ...[
            _buildSectionHeader('SERVERS'),
            const SizedBox(height: 8),
            _buildConfigTile(
              _webDav!,
              subtitle:
                  '$_webDavCount '
                  'server${_webDavCount != 1 ? 's' : ''}',
            ),
            const SizedBox(height: 16),
          ],

          // IPTV section. Rendered for a file-only setup too, so the note
          // explaining why those playlists can't be sent has somewhere to go.
          if (_iptvPlaylists?.isConfigured == true ||
              _iptvFavorites?.isConfigured == true ||
              _iptvLists?.isConfigured == true ||
              _iptvFileImported > 0) ...[
            _buildSectionHeader('IPTV'),
            const SizedBox(height: 8),
            if (_iptvPlaylists?.isConfigured == true)
              _buildConfigTile(
                _iptvPlaylists!,
                subtitle:
                    '$_iptvPlaylistCount '
                    'provider${_iptvPlaylistCount != 1 ? 's' : ''}',
              ),
            if (_iptvFavorites?.isConfigured == true)
              _buildConfigTile(
                _iptvFavorites!,
                subtitle:
                    '$_iptvFavoriteCount '
                    'channel${_iptvFavoriteCount != 1 ? 's' : ''}',
              ),
            if (_iptvLists?.isConfigured == true)
              _buildConfigTile(
                _iptvLists!,
                subtitle:
                    '$_iptvListCount '
                    'list${_iptvListCount != 1 ? 's' : ''} · '
                    '$_iptvListChannelCount channels',
              ),
            if (_streamBadges?.isConfigured == true)
              _buildConfigTile(
                _streamBadges!,
                subtitle:
                    '$_streamBadgeCount '
                    'ruleset${_streamBadgeCount != 1 ? 's' : ''}',
              ),
            if (_iptvFileImported > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(
                  '$_iptvFileImported playlist'
                  '${_iptvFileImported == 1 ? '' : 's'} imported from a file '
                  'can\'t be sent — import the file on the TV. Starred '
                  'channels from them still go across.',
                  style: TextStyle(
                    color: Colors.amber.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],

          const SizedBox(height: 8),

          // Send button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _hasAnySelected && _isPikpakPasswordValid && !_sending
                  ? _sendToTv
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                disabledBackgroundColor: const Color(
                  0xFF6366F1,
                ).withValues(alpha: 0.3),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Send to TV',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          if (_pikpak?.selected == true && !_isPikpakPasswordValid) ...[
            const SizedBox(height: 8),
            Text(
              'Enter PikPak password to continue',
              style: TextStyle(
                color: Colors.amber.withValues(alpha: 0.8),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.4),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1E293B),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Icon(
                Icons.settings_outlined,
                size: 36,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No services configured',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Set up Real-Debrid, Torbox, PikPak, or Trakt first',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigTile(_ConfigItem item, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => item.selected = !item.selected);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: item.selected
                    ? const Color(0xFF6366F1).withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _getIconColor(item.id).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getIcon(item.id),
                    color: _getIconColor(item.id),
                    size: 20,
                  ),
                ),

                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),

                // Checkbox
                Checkbox(
                  value: item.selected,
                  onChanged: (value) {
                    HapticFeedback.selectionClick();
                    setState(() => item.selected = value ?? false);
                  },
                  activeColor: const Color(0xFF6366F1),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPikPakTile() {
    final item = _pikpak!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: item.selected
                ? const Color(0xFF6366F1).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          children: [
            // Main tile
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => item.selected = !item.selected);
                },
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      // Icon
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.cloud,
                          color: Color(0xFF3B82F6),
                          size: 20,
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'PikPak',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'Connected account',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Checkbox
                      Checkbox(
                        value: item.selected,
                        onChanged: (value) {
                          HapticFeedback.selectionClick();
                          setState(() => item.selected = value ?? false);
                        },
                        activeColor: const Color(0xFF6366F1),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Password field (shown when selected)
            if (item.selected) ...[
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _pikpakPasswordController,
                  obscureText: !_showPikpakPassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    hintText: 'Enter your PikPak password',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPikpakPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: 20,
                      ),
                      onPressed: () {
                        setState(
                          () => _showPikpakPassword = !_showPikpakPassword,
                        );
                      },
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getIcon(String id) {
    switch (id) {
      case ConfigCommand.realDebrid:
        return Icons.speed;
      case ConfigCommand.torbox:
        return Icons.inventory_2;
      case ConfigCommand.premiumize:
        return Icons.workspace_premium_rounded;
      case ConfigCommand.allDebrid:
        return Icons.all_inclusive_rounded;
      case ConfigCommand.pikpak:
        return Icons.cloud;
      case ConfigCommand.trakt:
        return Icons.history_rounded;
      case ConfigCommand.simkl:
        return Icons.movie_filter_rounded;
      case ConfigCommand.mdblist:
        return Icons.list_alt_rounded;
      case ConfigCommand.searchEngines:
        return Icons.search;
      case ConfigCommand.webDav:
        return Icons.dns_rounded;
      case ConfigCommand.indexerManagers:
        return Icons.manage_search_rounded;
      case ConfigCommand.iptvPlaylists:
        return Icons.live_tv_rounded;
      case ConfigCommand.iptvFavorites:
        return Icons.star_rounded;
      case ConfigCommand.iptvLists:
        return Icons.playlist_play_rounded;
      case ConfigCommand.streamBadges:
        return Icons.sell_rounded;
      default:
        return Icons.settings;
    }
  }

  Color _getIconColor(String id) {
    switch (id) {
      case ConfigCommand.realDebrid:
        return const Color(0xFF10B981); // Green
      case ConfigCommand.torbox:
        return const Color(0xFFF59E0B); // Amber
      case ConfigCommand.premiumize:
        return const Color(0xFFFB923C); // Orange
      case ConfigCommand.allDebrid:
        return const Color(0xFF26A69A); // Teal
      case ConfigCommand.pikpak:
        return const Color(0xFF3B82F6); // Blue
      case ConfigCommand.trakt:
        return const Color(0xFFED1C24); // Trakt red
      case ConfigCommand.simkl:
        return const Color(0xFF22D3EE); // Simkl cyan
      case ConfigCommand.mdblist:
        return const Color(0xFF8B5CF6);
      case ConfigCommand.searchEngines:
        return const Color(0xFF8B5CF6); // Purple
      case ConfigCommand.webDav:
        return const Color(0xFF0EA5E9); // Sky
      case ConfigCommand.indexerManagers:
        return const Color(0xFFEAB308); // Yellow
      case ConfigCommand.iptvPlaylists:
        return const Color(0xFF14B8A6); // Teal
      case ConfigCommand.iptvFavorites:
        return const Color(0xFFF472B6); // Pink
      case ConfigCommand.iptvLists:
        return const Color(0xFFA78BFA); // Violet
      case ConfigCommand.streamBadges:
        return const Color(0xFFFBBF24); // Amber
      default:
        return Colors.white;
    }
  }
}
