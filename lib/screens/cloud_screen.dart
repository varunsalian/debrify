import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/analytics_service.dart';
import '../services/main_page_bridge.dart';
import '../services/storage_service.dart';

/// Stremio-style palette shared with the Search tab: an indigo/purple accent
/// over a deep near-black indigo base.
const Color _kStremioAccent = Color(0xFF7B5CFF);
const Color _kStremioBg = Color(0xFF0D0B1A);

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
        Icons.workspace_premium_rounded, Color(0xFFFB923C)),
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
    AnalyticsService.screenView('cloud');
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
    return Scaffold(
      backgroundColor: _kStremioBg,
      // Same soft purple bloom over deep indigo the Search tab uses.
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.75),
            radius: 1.35,
            colors: [
              Color(0xFF322A6B),
              Color(0xFF1A1734),
              Color(0xFF100E20),
              _kStremioBg,
            ],
            stops: [0.0, 0.42, 0.72, 1.0],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: _kStremioAccent))
              : _providers.isEmpty
                  ? _emptyState()
                  : _providerList(),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _kStremioAccent.withValues(alpha: 0.22),
                    _kStremioAccent.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                    color: _kStremioAccent.withValues(alpha: 0.35)),
              ),
              child: const Icon(Icons.cloud_off_rounded,
                  size: 40, color: _kStremioAccent),
            ),
            const SizedBox(height: 20),
            const Text(
              'No cloud providers connected',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect Real Debrid, Torbox, Premiumize, AllDebrid, PikPak, or '
              'WebDAV in Settings to manage your cloud files here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerList() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 2),
              child: Text(
                'Cloud',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: Colors.white,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 20),
              child: Text(
                'Choose a provider to manage its files',
                style: TextStyle(
                  fontSize: 14.5,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
            for (var i = 0; i < _providers.length; i++) ...[
              _providerTile(_providers[i], i),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }

  Widget _providerTile(_CloudProviderInfo p, int index) {
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
            color: Colors.transparent,
            child: InkWell(
              // The parent Focus owns keyboard/DPAD focus; keep InkWell out of
              // focus traversal so it doesn't create a competing focus node.
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(18),
              hoverColor: Colors.white.withValues(alpha: 0.03),
              onTap: () => _openProvider(p.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: focused
                        ? [
                            _kStremioAccent.withValues(alpha: 0.22),
                            _kStremioAccent.withValues(alpha: 0.07),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.055),
                            Colors.white.withValues(alpha: 0.02),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: focused
                        ? _kStremioAccent
                        : Colors.white.withValues(alpha: 0.08),
                    width: focused ? 1.6 : 1,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: _kStremioAccent.withValues(alpha: 0.30),
                            blurRadius: 22,
                            spreadRadius: -6,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    // Soft gradient icon tile in the provider's brand colour.
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            p.color.withValues(alpha: 0.30),
                            p.color.withValues(alpha: 0.12),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: p.color.withValues(alpha: 0.35)),
                      ),
                      child: Icon(
                        p.icon,
                        color: Colors.white.withValues(alpha: 0.92),
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.subtitle,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white
                          .withValues(alpha: focused ? 0.7 : 0.32),
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
