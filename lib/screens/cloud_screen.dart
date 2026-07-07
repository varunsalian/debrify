import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/main_page_bridge.dart';
import '../services/storage_service.dart';

/// Consolidated "Cloud" hub. Replaces the six separate provider nav tabs
/// (Real Debrid / Torbox / PikPak / Premiumize / AllDebrid / WebDAV) with a
/// single tab that lists the providers the user has enabled. Tapping one opens
/// that provider's existing screen as a pushed route (via
/// [MainPageBridge.openCloudProvider]), so all the provider logic is reused
/// unchanged and Back returns here.
class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key, this.isTelevision = false});

  final bool isTelevision;

  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudProviderInfo {
  const _CloudProviderInfo(
    this.key,
    this.name,
    this.subtitle,
    this.icon,
    this.color,
  );

  final String key;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _CloudScreenState extends State<CloudScreen> {
  /// Canonical provider order (mirrors the old per-provider nav order).
  static const List<_CloudProviderInfo> _allProviders = [
    _CloudProviderInfo('realdebrid', 'Real Debrid', 'Debrid service',
        Icons.cloud_download_rounded, Color(0xFF60A5FA)),
    _CloudProviderInfo('torbox', 'Torbox', 'Debrid service',
        Icons.flash_on_rounded, Color(0xFFFBBF24)),
    _CloudProviderInfo('pikpak', 'PikPak', 'Cloud storage',
        Icons.cloud_circle_rounded, Color(0xFF34D399)),
    _CloudProviderInfo('premiumize', 'Premiumize', 'Debrid service',
        Icons.workspace_premium_rounded, Color(0xFFF59E0B)),
    _CloudProviderInfo('alldebrid', 'AllDebrid', 'Debrid service',
        Icons.all_inclusive_rounded, Color(0xFFEF4444)),
    _CloudProviderInfo('webdav', 'WebDAV', 'File server',
        Icons.cloud_sync_rounded, Color(0xFF22D3EE)),
  ];

  /// Provider keys currently available (enabled & not hidden). Recomputed on
  /// load and whenever an integration setting changes.
  List<_CloudProviderInfo> _providers = [];
  bool _loading = true;

  /// One focus node per visible tile (Android TV DPAD navigation).
  final List<FocusNode> _nodes = [];

  /// The sidebar requested content focus before the async provider load
  /// finished (nodes didn't exist yet) — re-arm once tiles are built.
  bool _tvFocusPending = false;

  static const int _tabIndex = 16;

  @override
  void initState() {
    super.initState();
    MainPageBridge.addIntegrationListener(_onIntegrationsChanged);
    if (widget.isTelevision) {
      MainPageBridge.registerTvContentFocusHandler(_tabIndex, _focusFirstTile);
    }
    _load();
  }

  @override
  void dispose() {
    MainPageBridge.removeIntegrationListener(_onIntegrationsChanged);
    if (widget.isTelevision) {
      MainPageBridge.unregisterTvContentFocusHandler(
          _tabIndex, _focusFirstTile);
    }
    _disposeNodes();
    super.dispose();
  }

  void _disposeNodes() {
    for (final n in _nodes) {
      n.dispose();
    }
    _nodes.clear();
  }

  void _onIntegrationsChanged() => _load();

  Future<void> _load() async {
    final available = await _computeAvailableProviders();
    if (!mounted) return;
    setState(() {
      _providers = available;
      _syncNodes(available.length);
      _loading = false;
    });
    // If the sidebar handed us focus mid-load (before tiles existed), honor it
    // now that the tiles are built.
    if (_tvFocusPending && widget.isTelevision) _focusFirstTile();
  }

  /// Grow/shrink [_nodes] to match the visible tile count.
  void _syncNodes(int count) {
    while (_nodes.length < count) {
      _nodes.add(FocusNode(debugLabel: 'cloud_tile_${_nodes.length}'));
    }
    while (_nodes.length > count) {
      _nodes.removeLast().dispose();
    }
  }

  /// Which providers are enabled & not hidden — mirrors main.dart's
  /// `_computeVisibleNavIndices` per-provider conditions exactly.
  Future<List<_CloudProviderInfo>> _computeAvailableProviders() async {
    final keys = <String>{};

    final rdEnabled = await StorageService.getRealDebridIntegrationEnabled();
    final rdKey = await StorageService.getApiKey();
    final rdHidden = await StorageService.getRealDebridHiddenFromNav();
    if (rdEnabled && (rdKey?.isNotEmpty ?? false) && !rdHidden) {
      keys.add('realdebrid');
    }

    final tbEnabled = await StorageService.getTorboxIntegrationEnabled();
    final tbKey = await StorageService.getTorboxApiKey();
    final tbHidden = await StorageService.getTorboxHiddenFromNav();
    if (tbEnabled && (tbKey?.isNotEmpty ?? false) && !tbHidden) {
      keys.add('torbox');
    }

    final ppEnabled = await StorageService.getPikPakEnabled();
    final ppHidden = await StorageService.getPikPakHiddenFromNav();
    if (ppEnabled && !ppHidden) keys.add('pikpak');

    final pmEnabled = await StorageService.getPremiumizeIntegrationEnabled();
    final pmKey = await StorageService.getPremiumizeApiKey();
    final pmHidden = await StorageService.getPremiumizeHiddenFromNav();
    if (pmEnabled && (pmKey?.isNotEmpty ?? false) && !pmHidden) {
      keys.add('premiumize');
    }

    final adEnabled = await StorageService.getAllDebridIntegrationEnabled();
    final adKey = await StorageService.getAllDebridApiKey();
    final adHidden = await StorageService.getAllDebridHiddenFromNav();
    if (adEnabled && (adKey?.isNotEmpty ?? false) && !adHidden) {
      keys.add('alldebrid');
    }

    final webDavEnabled = await StorageService.getWebDavEnabled();
    final webDavServers = await StorageService.getWebDavServers();
    final wdHidden = await StorageService.getWebDavHiddenFromNav();
    if (webDavEnabled && webDavServers.isNotEmpty && !wdHidden) {
      keys.add('webdav');
    }

    return [
      for (final p in _allProviders)
        if (keys.contains(p.key)) p,
    ];
  }

  void _focusFirstTile() {
    if (!mounted) return;
    if (_nodes.isEmpty) {
      // Tiles not built yet (still loading) — re-arm; _load() retries when ready.
      _tvFocusPending = true;
      return;
    }
    _tvFocusPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _nodes.isNotEmpty) _nodes.first.requestFocus();
    });
  }

  void _openProvider(String key) => MainPageBridge.openCloudProvider?.call(key);

  KeyEventResult _onTileKey(FocusNode node, KeyEvent event, int index) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _nodes[index - 1].requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (index < _nodes.length - 1) {
        _nodes[index + 1].requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      // Left edge → hand focus back to the TV sidebar. Off-TV there's no
      // sidebar to focus, so let the event fall through (don't swallow it).
      final focusSidebar = MainPageBridge.focusTvSidebar;
      if (focusSidebar == null) return KeyEventResult.ignored;
      focusSidebar();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _openProvider(_providers[index].key);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _providers.isEmpty
                ? _emptyState(scheme)
                : _providerList(scheme),
      ),
    );
  }

  Widget _emptyState(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 56, color: scheme.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              'No cloud providers connected',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect Real Debrid, Torbox, Premiumize, AllDebrid, PikPak, or '
              'WebDAV in Settings to manage your cloud files here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerList(ColorScheme scheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              child: Text(
                'Cloud',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 16),
              child: Text(
                'Choose a provider to manage its files',
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            for (var i = 0; i < _providers.length; i++) ...[
              _providerTile(scheme, _providers[i], i),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _providerTile(ColorScheme scheme, _CloudProviderInfo p, int index) {
    return Focus(
      focusNode: index < _nodes.length ? _nodes[index] : null,
      onKeyEvent: (node, event) => _onTileKey(node, event, index),
      // Rebuild the tile when its focus state changes so the highlight tracks
      // DPAD focus (Focus.of(context).hasFocus alone doesn't trigger a rebuild).
      onFocusChange: (_) {
        if (mounted) setState(() {});
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Material(
            color: focused
                ? p.color.withValues(alpha: 0.16)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              // The parent Focus owns keyboard/DPAD focus; keep InkWell out of
              // focus traversal so it doesn't create a competing focus node.
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openProvider(p.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: focused ? p.color : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: p.color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(p.icon, color: p.color, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
