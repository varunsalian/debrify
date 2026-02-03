import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/storage_service.dart';
import '../../services/remote_control/remote_control_state.dart';
import '../../services/remote_control/remote_constants.dart';
import '../../services/engine/local_engine_storage.dart';
import 'addon_install_dialog.dart';

/// Widget for exporting setup/credentials to TV
class RemoteConfigExport extends StatefulWidget {
  final VoidCallback onBack;

  const RemoteConfigExport({
    super.key,
    required this.onBack,
  });

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
  _ConfigItem? _pikpak;
  _ConfigItem? _searchEngines;

  // API keys (loaded from storage)
  String? _realDebridApiKey;
  String? _torboxApiKey;
  String? _pikpakEmail;

  // PikPak password (entered by user)
  final _pikpakPasswordController = TextEditingController();
  bool _showPikpakPassword = false;

  // Search engine IDs
  List<String> _engineIds = [];

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
      _realDebridApiKey = await StorageService.getApiKey();
      final rdEnabled = await StorageService.getRealDebridIntegrationEnabled();
      final hasRd = _realDebridApiKey != null && _realDebridApiKey!.isNotEmpty && rdEnabled;

      // Load Torbox
      _torboxApiKey = await StorageService.getTorboxApiKey();
      final tbEnabled = await StorageService.getTorboxIntegrationEnabled();
      final hasTb = _torboxApiKey != null && _torboxApiKey!.isNotEmpty && tbEnabled;

      // Load PikPak
      _pikpakEmail = await StorageService.getPikPakEmail();
      final ppEnabled = await StorageService.getPikPakEnabled();
      final hasPp = _pikpakEmail != null && _pikpakEmail!.isNotEmpty && ppEnabled;

      // Load Search Engines
      await LocalEngineStorage.instance.initialize();
      _engineIds = await LocalEngineStorage.instance.getImportedEngineIds();
      final hasEngines = _engineIds.isNotEmpty;

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

        _pikpak = _ConfigItem(
          id: ConfigCommand.pikpak,
          name: 'PikPak',
          icon: 'pp',
          isConfigured: hasPp,
          selected: false, // Default to false since password needs to be entered
        );

        _searchEngines = _ConfigItem(
          id: ConfigCommand.searchEngines,
          name: 'Search Engines',
          icon: 'se',
          isConfigured: hasEngines,
          selected: hasEngines,
        );

        _loading = false;
      });
    } catch (e) {
      debugPrint('RemoteConfigExport: Failed to load configs: $e');
      setState(() => _loading = false);
    }
  }

  bool get _hasAnyConfigured {
    return (_realDebrid?.isConfigured ?? false) ||
        (_torbox?.isConfigured ?? false) ||
        (_pikpak?.isConfigured ?? false) ||
        (_searchEngines?.isConfigured ?? false);
  }

  bool get _hasAnySelected {
    return (_realDebrid?.selected ?? false) ||
        (_torbox?.selected ?? false) ||
        (_pikpak?.selected ?? false) ||
        (_searchEngines?.selected ?? false);
  }

  bool get _isPikpakPasswordValid {
    if (_pikpak?.selected != true) return true;
    return _pikpakPasswordController.text.isNotEmpty;
  }

  Future<void> _sendToTv() async {
    if (!_hasAnySelected || !_isPikpakPasswordValid) return;

    // Show TV picker dialog
    final choice = await AddonInstallDialog.show(
      context,
      'config',
      title: 'Select TV',
      subtitle: 'Send configuration to',
      showThisDevice: false,
    );
    if (choice == null || choice.target != 'tv' || choice.device == null) return;

    setState(() => _sending = true);
    HapticFeedback.mediumImpact();

    final targetIp = choice.device!.ip;
    final state = RemoteControlState();
    int successCount = 0;
    int failCount = 0;
    final List<String> results = [];

    try {
      // Send Real-Debrid
      if (_realDebrid?.selected == true && _realDebridApiKey != null) {
        final success = await state.sendConfigCommandToDevice(
          ConfigCommand.realDebrid,
          targetIp,
          configData: _realDebridApiKey,
        );
        if (success) {
          successCount++;
          results.add('Real-Debrid');
        } else {
          failCount++;
        }
      }

      // Send Torbox
      if (_torbox?.selected == true && _torboxApiKey != null) {
        final success = await state.sendConfigCommandToDevice(
          ConfigCommand.torbox,
          targetIp,
          configData: _torboxApiKey,
        );
        if (success) {
          successCount++;
          results.add('Torbox');
        } else {
          failCount++;
        }
      }

      // Send PikPak
      if (_pikpak?.selected == true && _pikpakEmail != null) {
        final pikpakData = jsonEncode({
          'email': _pikpakEmail,
          'password': _pikpakPasswordController.text,
        });
        final success = await state.sendConfigCommandToDevice(
          ConfigCommand.pikpak,
          targetIp,
          configData: pikpakData,
        );
        if (success) {
          successCount++;
          results.add('PikPak');
        } else {
          failCount++;
        }
      }

      // Send Search Engines
      if (_searchEngines?.selected == true && _engineIds.isNotEmpty) {
        final success = await state.sendConfigCommandToDevice(
          ConfigCommand.searchEngines,
          targetIp,
          configData: jsonEncode(_engineIds),
        );
        if (success) {
          successCount++;
          results.add('Search Engines');
        } else {
          failCount++;
        }
      }

      // Send complete signal to trigger TV restart (only if at least one succeeded)
      if (successCount > 0) {
        // Small delay to ensure previous commands are processed
        await Future.delayed(const Duration(milliseconds: 500));
        await state.sendConfigCommandToDevice(
          ConfigCommand.complete,
          targetIp,
        );
      }

      // Show result
      if (mounted) {
        if (failCount == 0 && successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sent ${results.join(", ")} to TV'),
              backgroundColor: const Color(0xFF10B981),
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
              content: Text('Sent ${results.join(", ")}, but some failed'),
              backgroundColor: const Color(0xFFF59E0B),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('RemoteConfigExport: Failed to send config: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
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
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
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
          if (_realDebrid?.isConfigured == true || _torbox?.isConfigured == true) ...[
            _buildSectionHeader('DEBRID PROVIDERS'),
            const SizedBox(height: 8),
            if (_realDebrid?.isConfigured == true)
              _buildConfigTile(_realDebrid!),
            if (_torbox?.isConfigured == true)
              _buildConfigTile(_torbox!),
            const SizedBox(height: 16),
          ],

          // PikPak section
          if (_pikpak?.isConfigured == true) ...[
            _buildSectionHeader('CLOUD STORAGE'),
            const SizedBox(height: 8),
            _buildPikPakTile(),
            const SizedBox(height: 16),
          ],

          // Search engines section
          if (_searchEngines?.isConfigured == true) ...[
            _buildSectionHeader('SEARCH'),
            const SizedBox(height: 8),
            _buildConfigTile(
              _searchEngines!,
              subtitle: '${_engineIds.length} engine${_engineIds.length != 1 ? 's' : ''}',
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
                disabledBackgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.3),
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
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
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
              'Set up Real-Debrid, Torbox, or PikPak first',
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
                          color: Colors.white,
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
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _pikpakEmail ?? '',
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
              Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.1),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _pikpakPasswordController,
                  obscureText: !_showPikpakPassword,
                  style: const TextStyle(color: Colors.white),
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
                        setState(() => _showPikpakPassword = !_showPikpakPassword);
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
      case ConfigCommand.pikpak:
        return Icons.cloud;
      case ConfigCommand.searchEngines:
        return Icons.search;
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
      case ConfigCommand.pikpak:
        return const Color(0xFF3B82F6); // Blue
      case ConfigCommand.searchEngines:
        return const Color(0xFF8B5CF6); // Purple
      default:
        return Colors.white;
    }
  }
}
