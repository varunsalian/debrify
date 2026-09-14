import 'widgets/settings_load_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/analytics_service.dart';
import '../../services/pikpak_api_service.dart';
import '../../services/profiles/profile_credential_facade.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

@visibleForTesting
bool pikPakProviderIsSelectable({
  required bool isAuthenticated,
  required bool secretPending,
}) => isAuthenticated && !secretPending;

/// Provider settings page for configuring default torrent provider.
class ProviderSettingsPage extends StatefulWidget {
  const ProviderSettingsPage({super.key});

  @override
  State<ProviderSettingsPage> createState() => _ProviderSettingsPageState();
}

class _ProviderSettingsPageState extends State<ProviderSettingsPage> {
  bool _loading = true;
  bool _loadFailed = false;
  int _loadGeneration = 0;
  String _selectedProvider = 'none';

  // Available providers based on connected services
  bool _torboxAvailable = false;
  bool _realDebridAvailable = false;
  bool _premiumizeAvailable = false;
  bool _allDebridAvailable = false;
  bool _pikpakAvailable = false;

  // Focus nodes for D-pad navigation
  final List<FocusNode> _providerFocusNodes = [];

  /// Which row wears the ring, DERIVED rather than remembered.
  ///
  /// This used to be a cached index with a hand-written falling edge ("focus
  /// left this row and no sibling claimed the ring — clear it"), which is the
  /// same workaround the rest of settings needed and for the same reason:
  /// Flutter can skip that notification entirely, and then the ghost ring the
  /// workaround exists to prevent lingers anyway. Asking the nodes is both
  /// shorter and always true — `indexWhere` already yields -1 for "nobody".
  int get _focusedIndex =>
      _providerFocusNodes.indexWhere((node) => node.hasFocus);

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('provider_settings');
    _loadSettings();
  }

  @override
  void dispose() {
    for (final node in _providerFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final (
        torboxAvailable,
        rdAvailable,
        premiumizeAvailable,
        allDebridAvailable,
        pikpakAvailable,
        currentProvider,
      ) = await (() async {
        // Check which providers are available
        final torboxConfigured = await StorageService.hasTorboxCredential();
        final rdConfigured = await StorageService.hasRealDebridCredential();
        final premiumizeConfigured =
            await StorageService.hasPremiumizeCredential();
        final allDebridConfigured =
            await StorageService.hasAllDebridCredential();
        final pikpakAuthenticated = await PikPakApiService.instance
            .isAuthenticated();
        final pikpakPresence = await ProfileCredentialFacade.isConfigured(
          'pikpak_email',
        );

        final torboxEnabled =
            await StorageService.getTorboxIntegrationEnabled();
        final rdEnabled =
            await StorageService.getRealDebridIntegrationEnabled();
        final premiumizeEnabled =
            await StorageService.getPremiumizeIntegrationEnabled();
        final allDebridEnabled =
            await StorageService.getAllDebridIntegrationEnabled();

        final torboxAvailable = torboxEnabled && torboxConfigured;
        final rdAvailable = rdEnabled && rdConfigured;
        final premiumizeAvailable = premiumizeEnabled && premiumizeConfigured;
        final allDebridAvailable = allDebridEnabled && allDebridConfigured;
        final pikpakAvailable = pikPakProviderIsSelectable(
          isAuthenticated: pikpakAuthenticated,
          secretPending: pikpakPresence.pending,
        );

        // Load current setting
        var currentProvider = await StorageService.getDefaultTorrentProvider();

        // Display an unavailable selection as 'Ask every time', but only a
        // deliberate selection may change the saved preference.
        if (currentProvider == 'torbox' && !torboxAvailable) {
          currentProvider = 'none';
        } else if (currentProvider == 'debrid' && !rdAvailable) {
          currentProvider = 'none';
        } else if (currentProvider == 'premiumize' && !premiumizeAvailable) {
          currentProvider = 'none';
        } else if (currentProvider == 'alldebrid' && !allDebridAvailable) {
          currentProvider = 'none';
        } else if (currentProvider == 'pikpak' && !pikpakAvailable) {
          currentProvider = 'none';
        }

        return (
          torboxAvailable,
          rdAvailable,
          premiumizeAvailable,
          allDebridAvailable,
          pikpakAvailable,
          currentProvider,
        );
      })().timeout(const Duration(seconds: 5));
      if (!mounted || generation != _loadGeneration) return;

      // Initialize focus nodes for available providers
      for (final node in _providerFocusNodes) {
        node.dispose();
      }
      _providerFocusNodes.clear();
      // +1 for "Ask every time" option
      final providerCount =
          1 +
          (torboxAvailable ? 1 : 0) +
          (rdAvailable ? 1 : 0) +
          (premiumizeAvailable ? 1 : 0) +
          (allDebridAvailable ? 1 : 0) +
          (pikpakAvailable ? 1 : 0);
      for (int i = 0; i < providerCount; i++) {
        final node = FocusNode(debugLabel: 'provider-$i');
        node.addListener(() => _onFocusChange(i));
        _providerFocusNodes.add(node);
      }

      if (mounted) {
        setState(() {
          _torboxAvailable = torboxAvailable;
          _realDebridAvailable = rdAvailable;
          _premiumizeAvailable = premiumizeAvailable;
          _allDebridAvailable = allDebridAvailable;
          _pikpakAvailable = pikpakAvailable;
          _selectedProvider = currentProvider;
          _loading = false;
        });
        // TV entry focus: land DPAD users on the first option instead of nothing.
        if (PlatformUtil.isTelevision) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || generation != _loadGeneration) return;
            // Don't yank focus if it already landed on a real node (only the
            // route's FocusScope holds focus while nothing is focused yet).
            final primary = FocusManager.instance.primaryFocus;
            if (primary != null && primary is! FocusScopeNode) return;
            if (_providerFocusNodes.isNotEmpty) {
              _providerFocusNodes.first.requestFocus();
            }
          });
        }
      }
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _onFocusChange(int index) {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _selectProvider(String provider) async {
    setState(() {
      _selectedProvider = provider;
    });
    await StorageService.setDefaultTorrentProvider(provider);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Default Provider',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadFailed) {
      return SettingsPageScaffold(
        title: 'Default Provider',
        body: SettingsLoadError(onRetry: _loadSettings),
      );
    }

    final hasAnyProvider =
        _torboxAvailable ||
        _realDebridAvailable ||
        _premiumizeAvailable ||
        _allDebridAvailable ||
        _pikpakAvailable;

    return SettingsPageScaffold(
      title: 'Default Provider',
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SettingsPageHeader(
                    icon: Icons.cloud_sync_rounded,
                    title: 'Default Provider',
                    subtitle: 'Configure default provider for adding torrents',
                  ),
                  const SizedBox(height: 24),
                  if (!hasAnyProvider) ...[
                    _buildNoProvidersMessage(context),
                  ] else ...[
                    _buildSection(
                      context,
                      title: 'Default Torrent Provider',
                      subtitle:
                          'Choose which service to use when adding torrents',
                      children: _buildProviderOptions(),
                    ),
                    const SizedBox(height: 16),
                    const SettingsInfoBanner(
                      text:
                          'You can also set this when adding a torrent by checking "Always use this provider".',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: app.shape.br(16),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: app.core.tx,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: t.dim)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  List<Widget> _buildProviderOptions() {
    final List<Widget> options = [];
    int nodeIndex = 0;

    // Always show "Ask every time" option
    options.add(
      _ProviderOption(
        focusNode: _providerFocusNodes[nodeIndex],
        isFocused: _focusedIndex == nodeIndex,
        icon: Icons.help_outline_rounded,
        title: 'Ask every time',
        subtitle: 'Show provider selection dialog',
        selected: _selectedProvider == 'none',
        onSelected: () => _selectProvider('none'),
      ),
    );
    nodeIndex++;

    // Torbox option
    if (_torboxAvailable) {
      options.add(const SizedBox(height: 8));
      options.add(
        _ProviderOption(
          focusNode: _providerFocusNodes[nodeIndex],
          isFocused: _focusedIndex == nodeIndex,
          icon: Icons.flash_on_rounded,
          title: 'Torbox',
          subtitle: 'Fast cloud torrent service',
          selected: _selectedProvider == 'torbox',
          onSelected: () => _selectProvider('torbox'),
        ),
      );
      nodeIndex++;
    }

    // Real-Debrid option
    if (_realDebridAvailable) {
      options.add(const SizedBox(height: 8));
      options.add(
        _ProviderOption(
          focusNode: _providerFocusNodes[nodeIndex],
          isFocused: _focusedIndex == nodeIndex,
          icon: Icons.cloud_rounded,
          title: 'Real-Debrid',
          subtitle: 'Premium link generator',
          selected: _selectedProvider == 'debrid',
          onSelected: () => _selectProvider('debrid'),
        ),
      );
      nodeIndex++;
    }

    // Premiumize option
    if (_premiumizeAvailable) {
      options.add(const SizedBox(height: 8));
      options.add(
        _ProviderOption(
          focusNode: _providerFocusNodes[nodeIndex],
          isFocused: _focusedIndex == nodeIndex,
          icon: Icons.workspace_premium_rounded,
          title: 'Premiumize',
          subtitle: 'Premium cloud downloader',
          selected: _selectedProvider == 'premiumize',
          onSelected: () => _selectProvider('premiumize'),
        ),
      );
      nodeIndex++;
    }

    // AllDebrid option
    if (_allDebridAvailable) {
      options.add(const SizedBox(height: 8));
      options.add(
        _ProviderOption(
          focusNode: _providerFocusNodes[nodeIndex],
          isFocused: _focusedIndex == nodeIndex,
          icon: Icons.all_inclusive_rounded,
          title: 'AllDebrid',
          subtitle: 'Premium link generator',
          selected: _selectedProvider == 'alldebrid',
          onSelected: () => _selectProvider('alldebrid'),
        ),
      );
      nodeIndex++;
    }

    // PikPak option
    if (_pikpakAvailable) {
      options.add(const SizedBox(height: 8));
      options.add(
        _ProviderOption(
          focusNode: _providerFocusNodes[nodeIndex],
          isFocused: _focusedIndex == nodeIndex,
          icon: Icons.folder_rounded,
          title: 'PikPak',
          subtitle: 'Cloud storage service',
          selected: _selectedProvider == 'pikpak',
          onSelected: () => _selectProvider('pikpak'),
        ),
      );
    }

    return options;
  }

  Widget _buildNoProvidersMessage(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.danger.withValues(alpha: 0.08),
        borderRadius: app.shape.br(16),
        border: Border.all(color: t.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: t.danger, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No providers connected',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.danger,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Connect Real-Debrid, Torbox, Premiumize, AllDebrid, or PikPak in Settings to use this feature.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: app.fade(app.core.tx, 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// D-pad compatible provider option widget
class _ProviderOption extends StatelessWidget {
  final FocusNode focusNode;
  final bool isFocused;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onSelected;

  const _ProviderOption({
    required this.focusNode,
    required this.isFocused,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (isActivateKey(event.logicalKey) ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          onSelected();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      // Snap, don't tween — animated focus decorations jank weak TV GPUs.
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? t.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: app.shape.br(12),
          border: Border.all(
            color: isFocused
                ? t.accent
                : selected
                ? t.accent.withValues(alpha: 0.5)
                : t.line,
            width: isFocused ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onSelected,
            // The outer Focus node owns DPAD focus/activation; a focusable
            // InkWell here would make each option two traversal stops.
            canRequestFocus: false,
            borderRadius: app.shape.br(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: app.fade(app.core.tx, 0.055),
                      borderRadius: app.shape.br(10),
                      border: Border.all(color: t.line),
                    ),
                    child: Icon(
                      icon,
                      color: selected || isFocused ? t.accent2 : t.dim,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: app.core.tx,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 12, color: t.dim),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: t.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        // Glyph inside an accent-FILLED circle.
                        color: app.inkOn(t.accent),
                        size: 16,
                      ),
                    )
                  else
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: t.dim2, width: 2),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
