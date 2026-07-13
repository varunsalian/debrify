import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/main_page_bridge.dart';
import 'widgets/settings_widgets.dart';

/// TV-only two-pane Settings shell (the "Mock 1" layout): a category rail on
/// the left, the selected category's rows on the right.
///
/// DPAD model — deliberately hand-wired (like the old connection grid) rather
/// than relying on Flutter's directional traversal, so behaviour is
/// deterministic on real TV hardware:
///   • Rail: Up/Down move between categories (and the pane updates live, so
///     you preview a category by focusing it). Right / OK enter the pane.
///     Left from the rail hands off to the app sidebar.
///   • Pane: Up/Down move between rows (auto-scrolling into view via the
///     default traversal's ensure-visible). Left returns to the *selected*
///     rail item (never a different category).
///
/// Only the TV layout is built here; phone/desktop keep the single-column
/// `_SettingsLayout`. All actions/dialogs still live in the parent State —
/// this is presentation + focus only.
class SettingsTvLayout extends StatefulWidget {
  final List<ConnectionInfo> connections;

  /// Focus target the sidebar hand-off and post-logout restores aim at —
  /// attached to the first rail item.
  final FocusNode? firstFocusNode;

  final Future<void> Function() onOpenHomePageSettings;
  final Future<void> Function() onOpenExternalPlayerSettings;
  final Future<void> Function() onOpenStartupSettings;
  final VoidCallback onOpenRemoteControl;
  final Future<void> Function() onOpenTorrentSettings;
  final Future<void> Function() onOpenFilterSettings;
  final Future<void> Function() onOpenProviderSettings;
  final Future<void> Function() onOpenQuickPlaySettings;
  final Future<void> Function() onOpenDebrifyTvSettings;
  final Future<void> Function() onClearDownloads;
  final Future<void> Function() onClearPlayback;
  final Future<void> Function() onCreateBackup;
  final Future<void> Function() onRestoreBackup;
  final Future<void> Function() onDangerAction;
  final String appVersion;
  final Future<void> Function() onCheckForUpdates;
  final String updateSubtitle;
  final bool checkingUpdates;
  final bool autoUpdateChecksEnabled;
  final ValueChanged<bool> onToggleAutoUpdateChecks;
  final bool showSupportDonation;
  final String supportDonationLabel;
  final String supportDonationSubtitle;
  final Future<void> Function() onOpenSupportDonation;

  const SettingsTvLayout({
    super.key,
    required this.connections,
    required this.firstFocusNode,
    required this.onOpenHomePageSettings,
    required this.onOpenExternalPlayerSettings,
    required this.onOpenStartupSettings,
    required this.onOpenRemoteControl,
    required this.onOpenTorrentSettings,
    required this.onOpenFilterSettings,
    required this.onOpenProviderSettings,
    required this.onOpenQuickPlaySettings,
    required this.onOpenDebrifyTvSettings,
    required this.onClearDownloads,
    required this.onClearPlayback,
    required this.onCreateBackup,
    required this.onRestoreBackup,
    required this.onDangerAction,
    required this.appVersion,
    required this.onCheckForUpdates,
    required this.updateSubtitle,
    required this.checkingUpdates,
    required this.autoUpdateChecksEnabled,
    required this.onToggleAutoUpdateChecks,
    required this.showSupportDonation,
    required this.supportDonationLabel,
    required this.supportDonationSubtitle,
    required this.onOpenSupportDonation,
  });

  @override
  State<SettingsTvLayout> createState() => _SettingsTvLayoutState();
}

class _Category {
  final IconData icon;
  final String label;
  const _Category(this.icon, this.label);
}

const List<_Category> _kCategories = [
  _Category(Icons.link_rounded, 'Connections'),
  _Category(Icons.tune_rounded, 'General'),
  _Category(Icons.search_rounded, 'Search'),
  _Category(Icons.live_tv_rounded, 'TV Mode'),
  _Category(Icons.storage_rounded, 'Data & Backup'),
  _Category(Icons.system_update_rounded, 'Updates'),
  _Category(Icons.favorite_rounded, 'Support'),
  _Category(Icons.warning_amber_rounded, 'Danger Zone'),
];

class _SettingsTvLayoutState extends State<SettingsTvLayout> {
  /// Max focusable rows in any single non-Connections category (General /
  /// Search / Data & Backup each have 4) — used to size the pane node pool.
  static const int _kMaxCategoryRows = 4;

  /// Selected category. A [ValueNotifier] (not setState) so a rail focus-move
  /// only rebuilds the pane and the two affected rail items via their
  /// [ValueListenableBuilder]s — not the whole two-pane tree (which, on
  /// Connections, means re-laying-out 10 cards per DPAD step on weak TVs).
  final ValueNotifier<int> _selected = ValueNotifier<int>(0);

  /// One node per category rail item — all owned here. The parent's
  /// [SettingsTvLayout.firstFocusNode] is NOT aliased to a rail item; it's a
  /// dedicated entry proxy (below) that redirects to the *currently selected*
  /// category, so bouncing out to the sidebar and back doesn't reset the pane.
  late final List<FocusNode> _railNodes;

  /// Pool of focus nodes for the pane rows, indexed top-to-bottom. Reused
  /// across categories (only one pane is shown at a time). A node whose
  /// `context` is null isn't attached to a row in the current category, which
  /// is how the DPAD wiring clamps at the pane's first/last visible row
  /// without tracking per-category row counts.
  late final List<FocusNode> _paneNodes;

  final ScrollController _paneScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _railNodes = List.generate(
      _kCategories.length,
      (i) => FocusNode(debugLabel: 'settings-tv-rail-$i'),
    );
    // The pool must cover the largest category. Connections has one row per
    // provider (widget.connections.length); every other category has at most
    // [_kMaxCategoryRows] rows (General / Search / Data & Backup = 4).
    final poolSize = widget.connections.length > _kMaxCategoryRows
        ? widget.connections.length
        : _kMaxCategoryRows;
    _paneNodes = List.generate(
      poolSize,
      (i) => FocusNode(debugLabel: 'settings-tv-pane-$i'),
    );
    widget.firstFocusNode?.addListener(_onEntryFocus);
  }

  @override
  void didUpdateWidget(SettingsTvLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.firstFocusNode != widget.firstFocusNode) {
      oldWidget.firstFocusNode?.removeListener(_onEntryFocus);
      widget.firstFocusNode?.addListener(_onEntryFocus);
    }
  }

  @override
  void dispose() {
    widget.firstFocusNode?.removeListener(_onEntryFocus);
    for (final n in _railNodes) {
      n.dispose();
    }
    for (final n in _paneNodes) {
      n.dispose();
    }
    _selected.dispose();
    _paneScroll.dispose();
    super.dispose();
  }

  /// The sidebar hand-off and logout restores focus [firstFocusNode]; redirect
  /// that onto the rail item for whatever category is currently showing.
  void _onEntryFocus() {
    if (!mounted) return;
    if (widget.firstFocusNode?.hasFocus ?? false) {
      _railNodes[_selected.value].requestFocus();
    }
  }

  void _select(int i) {
    if (i == _selected.value) return;
    _selected.value = i;
    // Reset scroll to top synchronously *before* the pane rebuilds. The
    // SingleChildScrollView (and its position) is reused across the
    // ValueListenableBuilder rebuild — only the inner keyed Column swaps — so
    // setting the offset now means the new category's pane paints at the top
    // on its first frame (a post-frame jumpTo would flash one stale-offset
    // frame first).
    if (_paneScroll.hasClients) _paneScroll.jumpTo(0);
  }

  // Enter the pane on the first row — via _focusPaneRow so it scrolls into
  // view. Without the scroll, re-entering a category whose pane was left
  // scrolled down would focus the (off-screen) top row with no visible
  // highlight.
  void _enterPane() {
    _focusPaneRow(0);
  }

  void _focusPaneRow(int i) {
    final node = _paneNodes[i];
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = node.context;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.15,
          duration: const Duration(milliseconds: 180),
        );
      }
    });
  }

  KeyEventResult _railKey(FocusNode node, KeyEvent event, int index) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      if (index > 0) _railNodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (index < _railNodes.length - 1) _railNodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _enterPane();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      // Always consume Left so focus never escapes the rail via directional
      // traversal, even if the sidebar hand-off isn't registered.
      MainPageBridge.focusTvSidebar?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _paneKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      // Return to the category we're viewing, not whichever rail item happens
      // to sit to the left geometrically.
      _railNodes[_selected.value].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      // Nothing to the right of the pane — trap so focus can't escape.
      return KeyEventResult.handled;
    }
    // Hand-wire Up/Down between the pane's visible rows, trapping at the ends
    // so directional traversal can never bounce focus back onto the rail.
    // A pooled node is "in the current category" only if its context is
    // mounted — the pool is reused across categories and a FocusNode's context
    // is NOT nulled on unmount, so `context != null` would be a stale true for
    // a node last attached by a larger, previously-visited category.
    final i = _paneNodes.indexWhere((n) => n.hasFocus);
    if (key == LogicalKeyboardKey.arrowUp) {
      if (i > 0 && _isPaneRowLive(i - 1)) _focusPaneRow(i - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (i >= 0 && i + 1 < _paneNodes.length && _isPaneRowLive(i + 1)) {
        _focusPaneRow(i + 1);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Whether pane node [i] is attached to a row mounted in the current pane.
  bool _isPaneRowLive(int i) => _paneNodes[i].context?.mounted ?? false;

  @override
  Widget build(BuildContext context) {
    return SettingsBackground(
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Invisible entry proxy: the parent State focuses [firstFocusNode]
            // on sidebar hand-off / logout restore; [_onEntryFocus] then
            // redirects to the selected category's rail item.
            if (widget.firstFocusNode != null)
              Focus(
                focusNode: widget.firstFocusNode,
                skipTraversal: true,
                descendantsAreFocusable: false,
                child: const SizedBox.shrink(),
              ),
            _buildRail(),
            Container(width: 1, color: kSettingsLine),
            // Only the pane rebuilds when the category changes.
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: _selected,
                builder: (context, selected, _) => _buildPane(selected),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRail() {
    return SizedBox(
      width: 300,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 14, bottom: 22),
              child: Text(
                'Settings',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: Colors.white,
                ),
              ),
            ),
            for (int i = 0; i < _kCategories.length; i++)
              _RailItem(
                index: i,
                category: _kCategories[i],
                focusNode: _railNodes[i],
                selected: _selected,
                onKey: _railKey,
                onActivate: _enterPane,
                onFocused: _select,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPane(int selected) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _paneKey,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: SingleChildScrollView(
          controller: _paneScroll,
          padding: const EdgeInsets.fromLTRB(32, 30, 40, 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              key: ValueKey<int>(selected),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 18),
                  child: Text(
                    _kCategories[selected].label,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      color: Colors.white,
                    ),
                  ),
                ),
                ..._buildPaneChildren(selected),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPaneChildren(int category) {
    switch (category) {
      case 0: // Connections
        return [
          for (int i = 0; i < widget.connections.length; i++) ...[
            if (i != 0) const SizedBox(height: 10),
            ConnectionCard(
              info: widget.connections[i],
              focusNode: _paneNodes[i],
              isLeftColumn: false,
            ),
          ],
        ];
      case 1: // General
        return [
          SettingsSection(
            title: '',
            children: [
              SettingsTile(
                icon: Icons.home_rounded,
                title: 'Home Page',
                subtitle: 'Default view when app opens',
                onTap: widget.onOpenHomePageSettings,
                focusNode: _paneNodes[0],
              ),
              SettingsTile(
                icon: Icons.open_in_new_rounded,
                title: 'Player Settings',
                subtitle: 'Configure preferred video player',
                onTap: widget.onOpenExternalPlayerSettings,
                focusNode: _paneNodes[1],
              ),
              SettingsTile(
                icon: Icons.rocket_launch_rounded,
                title: 'Startup',
                subtitle: 'Decide what happens on app launch',
                onTap: widget.onOpenStartupSettings,
                focusNode: _paneNodes[2],
              ),
              SettingsTile(
                icon: Icons.phonelink_rounded,
                title: 'Remote',
                subtitle: 'Send setup or receive from another device',
                onTap: () async => widget.onOpenRemoteControl(),
                focusNode: _paneNodes[3],
              ),
            ],
          ),
        ];
      case 2: // Search
        return [
          SettingsSection(
            title: '',
            children: [
              SettingsTile(
                icon: Icons.search_rounded,
                title: 'Search Settings',
                subtitle: 'Engines, filters, and sorting',
                onTap: widget.onOpenTorrentSettings,
                focusNode: _paneNodes[0],
              ),
              SettingsTile(
                icon: Icons.filter_list_rounded,
                title: 'Filter Settings',
                subtitle: 'Default quality, source, and language filters',
                onTap: widget.onOpenFilterSettings,
                focusNode: _paneNodes[1],
              ),
              SettingsTile(
                icon: Icons.cloud_sync_rounded,
                title: 'Provider Settings',
                subtitle: 'Default provider for adding torrents',
                onTap: widget.onOpenProviderSettings,
                focusNode: _paneNodes[2],
              ),
              SettingsTile(
                icon: Icons.bolt_rounded,
                title: 'Quick Play Settings',
                subtitle: 'Configure quick play for torrent search',
                onTap: widget.onOpenQuickPlaySettings,
                focusNode: _paneNodes[3],
              ),
            ],
          ),
        ];
      case 3: // TV Mode
        return [
          SettingsSection(
            title: '',
            children: [
              SettingsTile(
                icon: Icons.live_tv_rounded,
                title: 'Debrify TV Settings',
                subtitle: 'Limits, channels, and playback configuration',
                onTap: widget.onOpenDebrifyTvSettings,
                focusNode: _paneNodes[0],
              ),
            ],
          ),
        ];
      case 4: // Data & Backup
        return [
          const SettingsSectionLabel('Maintenance'),
          SettingsSection(
            title: '',
            children: [
              SettingsTile(
                icon: Icons.download_rounded,
                title: 'Clear Download Data',
                subtitle: 'Remove queue history and in-progress entries',
                onTap: widget.onClearDownloads,
                focusNode: _paneNodes[0],
              ),
              SettingsTile(
                icon: Icons.play_circle_rounded,
                title: 'Clear Playback Data',
                subtitle: 'Reset resume points and playback sessions',
                onTap: widget.onClearPlayback,
                focusNode: _paneNodes[1],
              ),
            ],
          ),
          const SizedBox(height: 18),
          const SettingsSectionLabel('Backup & Restore'),
          SettingsSection(
            title: '',
            children: [
              SettingsTile(
                icon: Icons.save_alt_rounded,
                title: 'Create Backup',
                subtitle: 'Save services, addons, and search engines to a file',
                onTap: widget.onCreateBackup,
                focusNode: _paneNodes[2],
              ),
              SettingsTile(
                icon: Icons.restore_rounded,
                title: 'Restore from Backup',
                subtitle: 'Import services and addons from a backup file',
                onTap: widget.onRestoreBackup,
                focusNode: _paneNodes[3],
              ),
            ],
          ),
        ];
      case 5: // Updates
        return [
          SettingsSection(
            title: '',
            children: [
              SettingsToggleTile(
                icon: Icons.notifications_active_rounded,
                title: 'Auto Check for Updates',
                subtitle: 'Notify about new releases on startup',
                value: widget.autoUpdateChecksEnabled,
                onChanged: widget.onToggleAutoUpdateChecks,
                focusNode: _paneNodes[0],
              ),
              SettingsTile(
                icon: Icons.system_update_rounded,
                title: 'Check for Updates',
                subtitle: widget.updateSubtitle,
                onTap: widget.onCheckForUpdates,
                tag: 'New',
                focusNode: _paneNodes[1],
                trailing: widget.checkingUpdates
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : null,
              ),
              SettingsInfoTile(
                icon: Icons.info_outline_rounded,
                title: 'Version',
                value: widget.appVersion,
              ),
            ],
          ),
        ];
      case 6: // Support
        // The donation row is conditional, so index the pane nodes off a
        // running counter to keep Up/Down wiring contiguous.
        int p = 0;
        return [
          SettingsSection(
            title: '',
            children: [
              if (widget.showSupportDonation)
                SettingsTile(
                  icon: Icons.favorite_rounded,
                  title: widget.supportDonationLabel,
                  subtitle: widget.supportDonationSubtitle,
                  onTap: widget.onOpenSupportDonation,
                  focusNode: _paneNodes[p++],
                ),
              SettingsTile(
                icon: Icons.forum_rounded,
                title: 'Reddit Community',
                subtitle: 'r/debrify - Questions, tips, and discussion',
                onTap: () =>
                    launchUrl(Uri.parse('https://www.reddit.com/r/debrify/')),
                focusNode: _paneNodes[p++],
              ),
              SettingsTile(
                icon: Icons.chat_rounded,
                title: 'Discord',
                subtitle: 'Join for help, updates, and discussion',
                onTap: () =>
                    launchUrl(Uri.parse('https://discord.gg/xuAc4Q2c9G')),
                focusNode: _paneNodes[p++],
              ),
              SettingsTile(
                icon: Icons.code_rounded,
                title: 'GitHub',
                subtitle: 'Source code and contributions',
                onTap: () => launchUrl(
                  Uri.parse('https://github.com/varunsalian/debrify'),
                ),
                focusNode: _paneNodes[p++],
              ),
            ],
          ),
        ];
      case 7: // Danger Zone
      default:
        return [
          SettingsSection(
            title: '',
            children: [
              SettingsTile(
                icon: Icons.warning_rounded,
                title: 'Reset Debrify',
                subtitle: 'Remove connections, preferences, and caches',
                onTap: widget.onDangerAction,
                destructive: true,
                focusNode: _paneNodes[0],
              ),
            ],
          ),
        ];
    }
  }
}

/// A single category rail item. Self-contained so a focus move only rebuilds
/// the two affected items (local `_focused`) and their selection tint (via the
/// shared [selected] notifier) — never the whole two-pane tree.
class _RailItem extends StatefulWidget {
  final int index;
  final _Category category;
  final FocusNode focusNode;
  final ValueNotifier<int> selected;
  final KeyEventResult Function(FocusNode, KeyEvent, int) onKey;
  final VoidCallback onActivate;
  final ValueChanged<int> onFocused;

  const _RailItem({
    required this.index,
    required this.category,
    required this.focusNode,
    required this.selected,
    required this.onKey,
    required this.onActivate,
    required this.onFocused,
  });

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Focus(
        // Key handler only — the InkWell below owns the focusable node, so
        // this wrapper must not be a focus target itself.
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) => widget.onKey(node, event, widget.index),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            focusNode: widget.focusNode,
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onActivate,
            onFocusChange: (f) {
              setState(() => _focused = f);
              if (f) widget.onFocused(widget.index);
            },
            child: ValueListenableBuilder<int>(
              valueListenable: widget.selected,
              builder: (context, sel, _) {
                final bool selected = sel == widget.index;
                final bool focused = _focused;
                final Color fg = (focused || selected)
                    ? Colors.white
                    : kSettingsDim;
                final Color iconColor = (focused || selected)
                    ? kSettingsAccent2
                    : kSettingsDim;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? (focused
                              ? kSettingsPanel2
                              : kSettingsAccent.withValues(alpha: 0.12))
                        : (focused ? kSettingsPanel2 : Colors.transparent),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: focused ? kSettingsAccent : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(widget.category.icon, size: 20, color: iconColor),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          widget.category.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
