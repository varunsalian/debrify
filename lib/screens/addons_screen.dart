import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/main_page_bridge.dart';
import 'settings/stremio_addons_page.dart';
import 'settings/engine_import_page.dart';

/// Screen for managing addons (Stremio and Torrent engines)
/// Contains two tabs: Stremio Addons and Torrent Addons
class AddonsScreen extends StatefulWidget {
  const AddonsScreen({super.key});

  /// Static callback to focus the current tab (for DPAD navigation from content)
  static VoidCallback? focusCurrentTab;

  @override
  State<AddonsScreen> createState() => _AddonsScreenState();
}

class _AddonsScreenState extends State<AddonsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Focus nodes for TV navigation
  final FocusNode _stremioTabFocusNode = FocusNode(debugLabel: 'stremio-tab');
  final FocusNode _torrentTabFocusNode = FocusNode(debugLabel: 'torrent-tab');

  // TV content focus handler
  VoidCallback? _tvContentFocusHandler;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Register TV sidebar focus handler (tab index 7 = Addons)
    _tvContentFocusHandler = () {
      // Focus the currently selected tab
      if (_tabController.index == 0) {
        _stremioTabFocusNode.requestFocus();
      } else {
        _torrentTabFocusNode.requestFocus();
      }
    };
    MainPageBridge.registerTvContentFocusHandler(7, _tvContentFocusHandler!);

    // Register callback for content to focus tab bar
    AddonsScreen.focusCurrentTab = () {
      if (_tabController.index == 0) {
        _stremioTabFocusNode.requestFocus();
      } else {
        _torrentTabFocusNode.requestFocus();
      }
    };
  }

  @override
  void dispose() {
    if (_tvContentFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(7, _tvContentFocusHandler!);
    }
    AddonsScreen.focusCurrentTab = null;
    _tabController.dispose();
    _stremioTabFocusNode.dispose();
    _torrentTabFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Addons'),
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _buildTabBar(theme),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          // Stremio Addons tab
          _StremioAddonsTabContent(),
          // Torrent Addons tab
          _TorrentAddonsTabContent(),
        ],
      ),
    );
  }

  Widget _buildTabBar(ThemeData theme) {
    final isSmallScreen = MediaQuery.of(context).size.width < 400;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: theme.colorScheme.onPrimaryContainer,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: isSmallScreen ? 12 : 14,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: isSmallScreen ? 12 : 14,
        ),
        labelPadding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 4 : 16),
        tabs: [
          _TabItem(
            icon: Icons.stream_rounded,
            label: isSmallScreen ? 'Stremio' : 'Stremio Addons',
            focusNode: _stremioTabFocusNode,
            onKeyEvent: (event) => _handleTabKeyEvent(event, 0),
            compact: isSmallScreen,
          ),
          _TabItem(
            icon: Icons.search_rounded,
            label: isSmallScreen ? 'Engines' : 'Torrent Engines',
            focusNode: _torrentTabFocusNode,
            onKeyEvent: (event) => _handleTabKeyEvent(event, 1),
            compact: isSmallScreen,
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleTabKeyEvent(KeyEvent event, int tabIndex) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (tabIndex == 1) {
          _stremioTabFocusNode.requestFocus();
          _tabController.animateTo(0);
          return KeyEventResult.handled;
        } else if (MainPageBridge.focusTvSidebar != null) {
          MainPageBridge.focusTvSidebar!();
          return KeyEventResult.handled;
        }
        break;
      case LogicalKeyboardKey.arrowRight:
        if (tabIndex == 0) {
          _torrentTabFocusNode.requestFocus();
          _tabController.animateTo(1);
          return KeyEventResult.handled;
        }
        break;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
        _tabController.animateTo(tabIndex);
        return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }
}

/// Custom tab item with focus support for TV navigation
class _TabItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent) onKeyEvent;
  final bool compact;

  const _TabItem({
    required this.icon,
    required this.label,
    required this.focusNode,
    required this.onKeyEvent,
    this.compact = false,
  });

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _isFocused = widget.focusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) => widget.onKeyEvent(event),
      child: Container(
        decoration: _isFocused
            ? BoxDecoration(
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(10),
              )
            : null,
        child: Tab(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: widget.compact ? 16 : 18),
              SizedBox(width: widget.compact ? 4 : 8),
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stremio Addons tab content - embeds the page content without Scaffold
class _StremioAddonsTabContent extends StatefulWidget {
  const _StremioAddonsTabContent();

  @override
  State<_StremioAddonsTabContent> createState() => _StremioAddonsTabContentState();
}

class _StremioAddonsTabContentState extends State<_StremioAddonsTabContent>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const StremioAddonsPageContent();
  }
}

/// Torrent Addons tab content - embeds the page content without Scaffold
class _TorrentAddonsTabContent extends StatefulWidget {
  const _TorrentAddonsTabContent();

  @override
  State<_TorrentAddonsTabContent> createState() => _TorrentAddonsTabContentState();
}

class _TorrentAddonsTabContentState extends State<_TorrentAddonsTabContent>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const EngineImportPageContent();
  }
}
