import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/indexer_manager_config.dart';
import '../../models/stremio_addon.dart';
import '../../models/webdav_item.dart';
import '../../services/engine/local_engine_storage.dart';
import '../../services/remote_control/remote_constants.dart';
import '../../services/remote_control/remote_control_state.dart';
import '../../services/storage_service.dart';
import '../../services/stremio_service.dart';

/// One-click "Transfer Everything" flow. Pushes all configured services
/// (debrid keys, Trakt session, search engines, PikPak, installed Stremio
/// addons) from this device to the currently connected receiver.
class RemoteTransferAll extends StatefulWidget {
  final VoidCallback onBack;

  const RemoteTransferAll({super.key, required this.onBack});

  @override
  State<RemoteTransferAll> createState() => _RemoteTransferAllState();
}

enum _ItemStatus { pending, sending, success, failure, skipped }

class _TransferItem {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  _ItemStatus status;

  _TransferItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
  }) : status = _ItemStatus.pending;
}

class _RemoteTransferAllState extends State<RemoteTransferAll> {
  bool _loading = true;
  bool _transferring = false;
  bool _done = false;

  String? _realDebridApiKey;
  String? _torboxApiKey;
  String? _premiumizeApiKey;
  String? _allDebridApiKey;
  String? _pikpakEmail;
  String? _traktAccessToken;
  String? _traktRefreshToken;
  int? _traktTokenExpiry;
  String? _traktUsername;
  List<String> _engineIds = [];
  List<StremioAddon> _addons = [];
  List<WebDavConfig> _webDavServers = [];
  List<IndexerManagerConfig> _indexerManagers = [];

  final _pikpakPasswordController = TextEditingController();
  bool _showPikpakPassword = false;

  final List<_TransferItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadBundle();
  }

  @override
  void dispose() {
    _pikpakPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadBundle() async {
    setState(() => _loading = true);

    try {
      _realDebridApiKey = await StorageService.getApiKey();
      final rdEnabled = await StorageService.getRealDebridIntegrationEnabled();
      final hasRd = (_realDebridApiKey?.isNotEmpty ?? false) && rdEnabled;

      _torboxApiKey = await StorageService.getTorboxApiKey();
      final tbEnabled = await StorageService.getTorboxIntegrationEnabled();
      final hasTb = (_torboxApiKey?.isNotEmpty ?? false) && tbEnabled;

      _premiumizeApiKey = await StorageService.getPremiumizeApiKey();
      final pmEnabled = await StorageService.getPremiumizeIntegrationEnabled();
      final hasPm = (_premiumizeApiKey?.isNotEmpty ?? false) && pmEnabled;

      _allDebridApiKey = await StorageService.getAllDebridApiKey();
      final adEnabled = await StorageService.getAllDebridIntegrationEnabled();
      final hasAd = (_allDebridApiKey?.isNotEmpty ?? false) && adEnabled;

      _pikpakEmail = await StorageService.getPikPakEmail();
      final ppEnabled = await StorageService.getPikPakEnabled();
      final hasPp = (_pikpakEmail?.isNotEmpty ?? false) && ppEnabled;

      _traktAccessToken = await StorageService.getTraktAccessToken();
      _traktRefreshToken = await StorageService.getTraktRefreshToken();
      _traktTokenExpiry = await StorageService.getTraktTokenExpiry();
      _traktUsername = await StorageService.getTraktUsername();
      final hasTrakt = (_traktAccessToken?.isNotEmpty ?? false) &&
          (_traktRefreshToken?.isNotEmpty ?? false);

      await LocalEngineStorage.instance.initialize();
      _engineIds = await LocalEngineStorage.instance.getImportedEngineIds();
      final hasEngines = _engineIds.isNotEmpty;

      try {
        _addons = await StremioService.instance.getAddons();
      } catch (e) {
        debugPrint('RemoteTransferAll: Failed to load addons: $e');
        _addons = [];
      }

      try {
        _webDavServers = await StorageService.getWebDavServers();
      } catch (e) {
        debugPrint('RemoteTransferAll: Failed to load WebDAV servers: $e');
        _webDavServers = [];
      }

      try {
        _indexerManagers = await StorageService.getIndexerManagerConfigs();
      } catch (e) {
        debugPrint(
          'RemoteTransferAll: Failed to load indexer manager configs: $e',
        );
        _indexerManagers = [];
      }
      final hasWebDav = _webDavServers.isNotEmpty;
      final hasIndexers = _indexerManagers.isNotEmpty;

      final items = <_TransferItem>[];
      if (hasRd) {
        items.add(_TransferItem(
          key: ConfigCommand.realDebrid,
          label: 'Real-Debrid',
          icon: Icons.speed,
          color: const Color(0xFF10B981),
        ));
      }
      if (hasTb) {
        items.add(_TransferItem(
          key: ConfigCommand.torbox,
          label: 'Torbox',
          icon: Icons.inventory_2,
          color: const Color(0xFFF59E0B),
        ));
      }
      if (hasPm) {
        items.add(_TransferItem(
          key: ConfigCommand.premiumize,
          label: 'Premiumize',
          icon: Icons.workspace_premium_rounded,
          color: const Color(0xFFFB923C),
        ));
      }
      if (hasAd) {
        items.add(_TransferItem(
          key: ConfigCommand.allDebrid,
          label: 'AllDebrid',
          icon: Icons.all_inclusive_rounded,
          color: const Color(0xFF26A69A),
        ));
      }
      if (hasPp) {
        items.add(_TransferItem(
          key: ConfigCommand.pikpak,
          label: 'PikPak',
          icon: Icons.cloud,
          color: const Color(0xFF3B82F6),
        ));
      }
      if (hasTrakt) {
        items.add(_TransferItem(
          key: ConfigCommand.trakt,
          label: _traktUsername != null
              ? 'Trakt (${_traktUsername!})'
              : 'Trakt',
          icon: Icons.history_rounded,
          color: const Color(0xFFED1C24),
        ));
      }
      if (hasEngines) {
        items.add(_TransferItem(
          key: ConfigCommand.searchEngines,
          label: 'Search Engines (${_engineIds.length})',
          icon: Icons.search,
          color: const Color(0xFF8B5CF6),
        ));
      }
      if (hasWebDav) {
        items.add(_TransferItem(
          key: ConfigCommand.webDav,
          label: 'WebDAV (${_webDavServers.length})',
          icon: Icons.dns_rounded,
          color: const Color(0xFF0EA5E9),
        ));
      }
      if (hasIndexers) {
        items.add(_TransferItem(
          key: ConfigCommand.indexerManagers,
          label: 'Jackett/Prowlarr (${_indexerManagers.length})',
          icon: Icons.manage_search_rounded,
          color: const Color(0xFFEAB308),
        ));
      }
      for (final addon in _addons) {
        items.add(_TransferItem(
          key: 'addon:${addon.manifestUrl}',
          label: 'Addon · ${addon.name}',
          icon: Icons.extension,
          color: const Color(0xFF6366F1),
        ));
      }

      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _loading = false;
      });
    } catch (e) {
      debugPrint('RemoteTransferAll: Failed to load bundle: $e');
      setState(() => _loading = false);
    }
  }

  bool get _hasPikpak =>
      _items.any((i) => i.key == ConfigCommand.pikpak);

  bool get _canStart {
    if (_items.isEmpty || _transferring || _done) return false;
    if (_hasPikpak && _pikpakPasswordController.text.isEmpty) return false;
    return true;
  }

  Future<void> _start() async {
    final state = RemoteControlState();
    final target = state.connectedDevice;
    if (target == null) {
      _toast('Not connected to a device', error: true);
      return;
    }

    setState(() {
      _transferring = true;
      _done = false;
    });
    HapticFeedback.mediumImpact();

    int success = 0;
    int failure = 0;

    for (final item in _items) {
      if (!mounted) return;
      setState(() => item.status = _ItemStatus.sending);

      bool ok = false;
      try {
        if (item.key.startsWith('addon:')) {
          final url = item.key.substring('addon:'.length);
          ok = await state.sendAddonCommandToDevice(
            AddonCommand.install,
            target.ip,
            manifestUrl: url,
          );
        } else {
          ok = await _sendConfigItem(state, target.ip, item.key);
        }
      } catch (e) {
        debugPrint('RemoteTransferAll: Item ${item.key} threw: $e');
        ok = false;
      }

      if (!mounted) return;
      setState(() {
        item.status = ok ? _ItemStatus.success : _ItemStatus.failure;
      });
      if (ok) {
        success++;
      } else {
        failure++;
      }

      await Future.delayed(const Duration(milliseconds: 250));
    }

    if (success > 0) {
      await Future.delayed(const Duration(milliseconds: 400));
      await state.sendConfigCommandToDevice(
        ConfigCommand.complete,
        target.ip,
      );
    }

    if (!mounted) return;
    setState(() {
      _transferring = false;
      _done = true;
    });

    if (failure == 0) {
      _toast('Transferred $success item${success == 1 ? '' : 's'}');
    } else if (success == 0) {
      _toast('Transfer failed', error: true);
    } else {
      _toast('Transferred $success, $failure failed', warning: true);
    }
  }

  Future<bool> _sendConfigItem(
    RemoteControlState state,
    String targetIp,
    String key,
  ) {
    switch (key) {
      case ConfigCommand.realDebrid:
        return state.sendConfigCommandToDevice(
          ConfigCommand.realDebrid,
          targetIp,
          configData: _realDebridApiKey,
        );
      case ConfigCommand.torbox:
        return state.sendConfigCommandToDevice(
          ConfigCommand.torbox,
          targetIp,
          configData: _torboxApiKey,
        );
      case ConfigCommand.premiumize:
        return state.sendConfigCommandToDevice(
          ConfigCommand.premiumize,
          targetIp,
          configData: _premiumizeApiKey,
        );
      case ConfigCommand.allDebrid:
        return state.sendConfigCommandToDevice(
          ConfigCommand.allDebrid,
          targetIp,
          configData: _allDebridApiKey,
        );
      case ConfigCommand.pikpak:
        return state.sendConfigCommandToDevice(
          ConfigCommand.pikpak,
          targetIp,
          configData: jsonEncode({
            'email': _pikpakEmail,
            'password': _pikpakPasswordController.text,
          }),
        );
      case ConfigCommand.trakt:
        return state.sendConfigCommandToDevice(
          ConfigCommand.trakt,
          targetIp,
          configData: jsonEncode({
            'access_token': _traktAccessToken,
            'refresh_token': _traktRefreshToken,
            if (_traktTokenExpiry != null) 'expiry_ms': _traktTokenExpiry,
            if (_traktUsername != null) 'username': _traktUsername,
          }),
        );
      case ConfigCommand.searchEngines:
        return state.sendConfigCommandToDevice(
          ConfigCommand.searchEngines,
          targetIp,
          configData: jsonEncode(_engineIds),
        );
      case ConfigCommand.webDav:
        return state.sendConfigCommandToDevice(
          ConfigCommand.webDav,
          targetIp,
          configData: jsonEncode(
            _webDavServers.map((s) => s.toJson()).toList(),
          ),
        );
      case ConfigCommand.indexerManagers:
        return state.sendConfigCommandToDevice(
          ConfigCommand.indexerManagers,
          targetIp,
          configData: jsonEncode(
            _indexerManagers.map((c) => c.toJson()).toList(),
          ),
        );
      default:
        return Future.value(false);
    }
  }

  void _toast(String msg, {bool error = false, bool warning = false}) {
    if (!mounted) return;
    final color = error
        ? const Color(0xFFEF4444)
        : warning
            ? const Color(0xFFF59E0B)
            : const Color(0xFF10B981);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: _transferring ? null : widget.onBack,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back to menu'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Transfer Everything',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Send all configured services and installed addons to the '
          'connected device in one go.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            ),
          )
        else if (_items.isEmpty)
          _buildEmpty()
        else ...[
          if (_hasPikpak) _buildPikpakPassword(),
          ..._items.map(_buildItemTile),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canStart ? _start : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                disabledBackgroundColor:
                    const Color(0xFF6366F1).withValues(alpha: 0.3),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _transferring
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_done ? Icons.check : Icons.send, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _done ? 'Done' : 'Transfer Everything',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (_hasPikpak &&
              _pikpakPasswordController.text.isEmpty &&
              !_transferring) ...[
            const SizedBox(height: 8),
            Text(
              'Enter PikPak password to enable transfer',
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

  Widget _buildEmpty() {
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
                Icons.inbox_outlined,
                size: 36,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing to transfer',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Set up a debrid provider, Trakt, search engines, or addons '
              'first.',
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

  Widget _buildPikpakPassword() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud,
                    color: Color(0xFF3B82F6), size: 18),
                const SizedBox(width: 8),
                Text(
                  'PikPak password',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _pikpakEmail ?? '',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pikpakPasswordController,
              obscureText: !_showPikpakPassword,
              enabled: !_transferring && !_done,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter password',
                hintStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.3)),
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
                  onPressed: () => setState(
                    () => _showPikpakPassword = !_showPikpakPassword,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(_TransferItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(item.icon, color: item.color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            _buildStatus(item.status),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(_ItemStatus status) {
    switch (status) {
      case _ItemStatus.pending:
        return Icon(
          Icons.radio_button_unchecked,
          color: Colors.white.withValues(alpha: 0.25),
          size: 18,
        );
      case _ItemStatus.sending:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
          ),
        );
      case _ItemStatus.success:
        return const Icon(Icons.check_circle,
            color: Color(0xFF10B981), size: 18);
      case _ItemStatus.failure:
        return const Icon(Icons.error,
            color: Color(0xFFEF4444), size: 18);
      case _ItemStatus.skipped:
        return Icon(Icons.remove_circle_outline,
            color: Colors.white.withValues(alpha: 0.3), size: 18);
    }
  }
}
