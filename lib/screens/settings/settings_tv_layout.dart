import 'package:flutter/material.dart';
import '../../utils/tv_reveal.dart';
import 'package:flutter/services.dart';

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

  /// Watch-history services (Trakt, Simkl, MDBList) — their own rail category
  /// rather than three more cards in Connections, which had grown to ten.
  final List<ConnectionInfo> trackers;

  /// Focus target the sidebar hand-off and post-logout restores aim at —
  /// attached to the first rail item.
  final FocusNode? firstFocusNode;

  /// Opens the full-screen settings search (the rail's search item / OK / Right).
  final VoidCallback onOpenSearch;

  final Future<void> Function() onOpenHomePageSettings;
  final Future<void> Function() onOpenExternalPlayerSettings;
  final VoidCallback onOpenRemoteControl;
  final Future<void> Function() onOpenTorrentSettings;
  final Future<void> Function() onOpenFilterSettings;
  final Future<void> Function() onOpenProviderSettings;
  final Future<void> Function() onOpenQuickPlaySettings;
  final Future<void> Function() onOpenDebrifyTvSettings;
  final Future<void> Function() onClearDownloads;
  final Future<void> Function() onClearPlayback;
  // Android-only custom download folder (SAF); null hides the row.
  final Future<void> Function()? onOpenDownloadLocation;
  final String downloadLocationSubtitle;
  final Future<void> Function() onCreateBackup;
  final Future<void> Function() onRestoreBackup;
  final Future<void> Function() onDangerAction;
  final String appVersion;
  final Future<void> Function() onCheckForUpdates;
  final String updateSubtitle;
  final bool checkingUpdates;
  final bool autoUpdateChecksEnabled;
  final ValueChanged<bool> onToggleAutoUpdateChecks;
  final bool tvKeyboardEnabled;
  final ValueChanged<bool> onToggleTvKeyboard;
  // Screen size: percentage of the panel's native density the UI is laid out
  // at — 100 is the panel's own size, and smaller fits more on screen. Held
  // here only to caption the row; the picker itself is its own page.
  final int tvUiScalePercent;
  final Future<void> Function() onOpenTvScreenSize;
  // Home layout: which TV home view is active. Held here only to caption the
  // row; the picker itself is its own page.
  final String tvHomeStyleLabel;
  final Future<void> Function() onOpenTvHomeStyle;
  final bool showSupportDonation;
  final String supportDonationLabel;
  final String supportDonationSubtitle;
  final Future<void> Function() onOpenSupportDonation;

  const SettingsTvLayout({
    super.key,
    required this.connections,
    required this.trackers,
    required this.firstFocusNode,
    required this.onOpenSearch,
    required this.onOpenHomePageSettings,
    required this.onOpenExternalPlayerSettings,
    required this.onOpenRemoteControl,
    required this.onOpenTorrentSettings,
    required this.onOpenFilterSettings,
    required this.onOpenProviderSettings,
    required this.onOpenQuickPlaySettings,
    required this.onOpenDebrifyTvSettings,
    required this.onClearDownloads,
    required this.onClearPlayback,
    this.onOpenDownloadLocation,
    this.downloadLocationSubtitle = '',
    required this.onCreateBackup,
    required this.onRestoreBackup,
    required this.onDangerAction,
    required this.appVersion,
    required this.onCheckForUpdates,
    required this.updateSubtitle,
    required this.checkingUpdates,
    required this.autoUpdateChecksEnabled,
    required this.onToggleAutoUpdateChecks,
    required this.tvKeyboardEnabled,
    required this.onToggleTvKeyboard,
    required this.tvUiScalePercent,
    required this.onOpenTvScreenSize,
    required this.tvHomeStyleLabel,
    required this.onOpenTvHomeStyle,
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

  /// One-line hint of what the category holds, shown under [label] in the
  /// rail so a glance down the list previews each section's contents.
  final String subtitle;
  const _Category(this.icon, this.label, this.subtitle);
}

const List<_Category> _kCategories = [
  _Category(Icons.link_rounded, 'Connections', 'Debrid, cloud, IPTV & more'),
  _Category(Icons.sync_rounded, 'Trackers', 'Trakt & Simkl watch history'),
  _Category(Icons.tune_rounded, 'General', 'Home, player & remote'),
  _Category(Icons.search_rounded, 'Search', 'Engines, filters & providers'),
  _Category(
    Icons.live_tv_rounded,
    'TV Mode',
    'Debrify TV, keyboard & screen size',
  ),
  _Category(
    Icons.storage_rounded,
    'Data & Backup',
    'Downloads, backup & restore',
  ),
  _Category(Icons.system_update_rounded, 'Updates', 'Version & auto-update'),
  _Category(Icons.favorite_rounded, 'Support', 'Donate & community links'),
  _Category(Icons.warning_amber_rounded, 'Danger Zone', 'Reset Debrify'),
];

class _SettingsTvLayoutState extends State<SettingsTvLayout> {
  /// Max focusable rows in any single FIXED category — one whose rows are
  /// written out here rather than driven by a provider list (Data & Backup has
  /// up to 5 with the download-location row). Connections and Trackers are
  /// sized from their own lists; see the pool computation in [initState].
  static const int _kMaxCategoryRows = 5;

  /// Selected category. A [ValueNotifier] (not setState) so a rail focus-move
  /// only rebuilds the pane and the two affected rail items via their
  /// [ValueListenableBuilder]s — not the whole two-pane tree (which, on
  /// Connections, means re-laying-out every provider card per DPAD step on
  /// weak TVs).
  final ValueNotifier<int> _selected = ValueNotifier<int>(0);

  /// One node per category rail item — all owned here. The parent's
  /// [SettingsTvLayout.firstFocusNode] is NOT aliased to a rail item; it's a
  /// dedicated entry proxy (below) that redirects to the *currently selected*
  /// category, so bouncing out to the sidebar and back doesn't reset the pane.
  late final List<FocusNode> _railNodes;

  /// The search item sits above the category rail — its own node so Up from the
  /// first category lands here and Down from here returns to the categories.
  final FocusNode _searchNode = FocusNode(
    debugLabel: 'settings-tv-rail-search',
  );

  /// Pool of focus nodes for the pane rows, indexed top-to-bottom. Reused
  /// across categories (only one pane is shown at a time). A node whose
  /// `context` is null isn't attached to a row in the current category, which
  /// is how the DPAD wiring clamps at the pane's first/last visible row
  /// without tracking per-category row counts.
  late final List<FocusNode> _paneNodes;

  final ScrollController _paneScroll = ScrollController();

  /// The rail is scrollable so the taller two-line items + search entry can't
  /// overflow a short TV surface (e.g. 540-logical-px panels); focused items
  /// are revealed into view like the pane's rows.
  final ScrollController _railScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _railNodes = List.generate(
      _kCategories.length,
      (i) => FocusNode(debugLabel: 'settings-tv-rail-$i'),
    );
    // The pool must cover whichever category has the most rows. Connections
    // and Trackers each have one row per provider; the fixed categories have
    // at most [_kMaxCategoryRows]. Computed over all three rather than
    // assuming Connections is always the biggest — it no longer holds every
    // provider.
    var poolSize = _kMaxCategoryRows;
    for (final n in [widget.connections.length, widget.trackers.length]) {
      if (n > poolSize) poolSize = n;
    }
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
    _searchNode.dispose();
    _selected.dispose();
    _paneScroll.dispose();
    _railScroll.dispose();
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
        tvRevealMinimal(ctx);
      }
    });
  }

  KeyEventResult _railKey(FocusNode node, KeyEvent event, int index) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      // Above the first category sits the search item.
      if (index > 0) {
        _railNodes[index - 1].requestFocus();
      } else {
        _searchNode.requestFocus();
      }
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

  /// DPAD for the rail's search item: Down enters the category list, Right/OK
  /// opens search, Left hands off to the sidebar, Up is trapped (topmost).
  KeyEventResult _searchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _railNodes[0].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onOpenSearch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
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
      width: 320,
      child: SingleChildScrollView(
        controller: _railScroll,
        padding: const EdgeInsets.fromLTRB(24, 28, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 14, bottom: 18),
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
            _RailSearchItem(
              focusNode: _searchNode,
              onKey: _searchKey,
              onActivate: widget.onOpenSearch,
            ),
            const SizedBox(height: 12),
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
      case 1: // Trackers
        return [
          for (int i = 0; i < widget.trackers.length; i++) ...[
            if (i != 0) const SizedBox(height: 10),
            ConnectionCard(
              info: widget.trackers[i],
              focusNode: _paneNodes[i],
              isLeftColumn: false,
            ),
          ],
        ];
      case 2: // General
        return [
          SettingsSection(
            title: '',
            children: [
              SettingsTile.spec(
                SettingsRows.homePage,
                onTap: widget.onOpenHomePageSettings,
                focusNode: _paneNodes[0],
              ),
              SettingsTile.spec(
                SettingsRows.player,
                onTap: widget.onOpenExternalPlayerSettings,
                focusNode: _paneNodes[1],
              ),
              SettingsTile.spec(
                SettingsRows.remote,
                onTap: () async => widget.onOpenRemoteControl(),
                focusNode: _paneNodes[2],
              ),
            ],
          ),
        ];
      case 3: // Search
        return [
          SettingsSection(
            title: '',
            children: [
              SettingsTile.spec(
                SettingsRows.searchSettings,
                onTap: widget.onOpenTorrentSettings,
                focusNode: _paneNodes[0],
              ),
              SettingsTile.spec(
                SettingsRows.filterSettings,
                onTap: widget.onOpenFilterSettings,
                focusNode: _paneNodes[1],
              ),
              SettingsTile.spec(
                SettingsRows.providerSettings,
                onTap: widget.onOpenProviderSettings,
                focusNode: _paneNodes[2],
              ),
              SettingsTile.spec(
                SettingsRows.quickPlay,
                onTap: widget.onOpenQuickPlaySettings,
                focusNode: _paneNodes[3],
              ),
            ],
          ),
        ];
      case 4: // TV Mode
        return [
          SettingsSection(
            title: '',
            children: [
              SettingsTile.spec(
                SettingsRows.debrifyTv,
                onTap: widget.onOpenDebrifyTvSettings,
                focusNode: _paneNodes[0],
              ),
              SettingsToggleTile.spec(
                SettingsRows.tvKeyboard,
                value: widget.tvKeyboardEnabled,
                onChanged: widget.onToggleTvKeyboard,
                focusNode: _paneNodes[1],
              ),
              SettingsTile.spec(
                SettingsRows.tvScreenSize,
                subtitle: tvUiScaleLabel(widget.tvUiScalePercent),
                onTap: widget.onOpenTvScreenSize,
                focusNode: _paneNodes[2],
              ),
              SettingsTile.spec(
                SettingsRows.tvHomeStyle,
                subtitle: widget.tvHomeStyleLabel,
                onTap: widget.onOpenTvHomeStyle,
                focusNode: _paneNodes[3],
              ),
            ],
          ),
        ];
      case 5: // Data & Backup
        {
          // Focus nodes are claimed sequentially so the optional
          // download-location row doesn't shift hardcoded indices.
          int paneIdx = 0;
          FocusNode nextNode() => _paneNodes[paneIdx++];
          return [
            if (widget.onOpenDownloadLocation != null) ...[
              const SettingsSectionLabel('Downloads'),
              SettingsSection(
                title: '',
                children: [
                  SettingsTile.spec(
                    SettingsRows.downloadLocation,
                    subtitle: widget.downloadLocationSubtitle,
                    onTap: widget.onOpenDownloadLocation!,
                    focusNode: nextNode(),
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],
            const SettingsSectionLabel('Maintenance'),
            SettingsSection(
              title: '',
              children: [
                SettingsTile.spec(
                  SettingsRows.clearDownloads,
                  onTap: widget.onClearDownloads,
                  focusNode: nextNode(),
                ),
                SettingsTile.spec(
                  SettingsRows.clearPlayback,
                  onTap: widget.onClearPlayback,
                  focusNode: nextNode(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const SettingsSectionLabel('Backup & Restore'),
            SettingsSection(
              title: '',
              children: [
                SettingsTile.spec(
                  SettingsRows.createBackup,
                  onTap: widget.onCreateBackup,
                  focusNode: nextNode(),
                ),
                SettingsTile.spec(
                  SettingsRows.restoreBackup,
                  onTap: widget.onRestoreBackup,
                  focusNode: nextNode(),
                ),
              ],
            ),
          ];
        }
      case 6: // Updates
        return [
          SettingsSection(
            title: '',
            children: [
              SettingsToggleTile.spec(
                SettingsRows.autoUpdate,
                value: widget.autoUpdateChecksEnabled,
                onChanged: widget.onToggleAutoUpdateChecks,
                focusNode: _paneNodes[0],
              ),
              SettingsTile.spec(
                SettingsRows.checkUpdates,
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
              SettingsInfoTile.spec(
                SettingsRows.version,
                value: widget.appVersion,
              ),
            ],
          ),
        ];
      case 7: // Support
        // The donation row is conditional, so index the pane nodes off a
        // running counter to keep Up/Down wiring contiguous.
        int p = 0;
        return [
          SettingsSection(
            title: '',
            children: [
              if (widget.showSupportDonation)
                SettingsTile(
                  icon: SettingsRows.supportDebrify.icon,
                  title: widget.supportDonationLabel,
                  subtitle: widget.supportDonationSubtitle,
                  onTap: widget.onOpenSupportDonation,
                  focusNode: _paneNodes[p++],
                ),
              SettingsTile.spec(
                SettingsRows.reddit,
                onTap: () => launchSettingsUrl(SettingsRows.reddit.url!),
                focusNode: _paneNodes[p++],
              ),
              SettingsTile.spec(
                SettingsRows.discord,
                onTap: () => launchSettingsUrl(SettingsRows.discord.url!),
                focusNode: _paneNodes[p++],
              ),
              SettingsTile.spec(
                SettingsRows.github,
                onTap: () => launchSettingsUrl(SettingsRows.github.url!),
                focusNode: _paneNodes[p++],
              ),
            ],
          ),
        ];
      case 8: // Danger Zone
        return [
          SettingsSection(
            title: '',
            children: [
              SettingsTile.spec(
                SettingsRows.resetDebrify,
                onTap: widget.onDangerAction,
                destructive: true,
                focusNode: _paneNodes[0],
              ),
            ],
          ),
        ];
      // Deliberately NOT sharing a body with Danger Zone, which is how this
      // read before: an index nobody wrote a case for used to fall through
      // and render Reset Debrify. A forgotten case should show nothing, never
      // the destructive pane.
      default:
        return const [];
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
              if (f) {
                widget.onFocused(widget.index);
                // Scroll the focused item into view — the rail scrolls now.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && context.mounted) tvRevealMinimal(context);
                });
              }
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
                // Subtitle brightens with the row but stays a step dimmer than
                // the title so the label still reads as primary.
                final Color subColor = (focused || selected)
                    ? Colors.white.withValues(alpha: 0.60)
                    : kSettingsDim2;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
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
                            const SizedBox(height: 2),
                            Text(
                              widget.category.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.2,
                                fontWeight: FontWeight.w500,
                                color: subColor,
                              ),
                            ),
                          ],
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

/// Search entry at the top of the rail — looks like a search field, opens the
/// full-screen [SettingsSearchPage]. Self-contained (local `_focused`) so a
/// focus move only rebuilds this item, matching [_RailItem].
class _RailSearchItem extends StatefulWidget {
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final VoidCallback onActivate;

  const _RailSearchItem({
    required this.focusNode,
    required this.onKey,
    required this.onActivate,
  });

  @override
  State<_RailSearchItem> createState() => _RailSearchItemState();
}

class _RailSearchItemState extends State<_RailSearchItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bool focused = _focused;
    final Color fg = focused ? Colors.white : kSettingsDim;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: widget.onKey,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            focusNode: widget.focusNode,
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onActivate,
            onFocusChange: (f) {
              setState(() => _focused = f);
              if (f) {
                // Reveal the top of the rail (search sits above category 0).
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && context.mounted) tvRevealMinimal(context);
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: focused ? kSettingsPanel2 : kSettingsPanel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: focused ? kSettingsAccent : kSettingsLine,
                  width: focused ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: focused ? kSettingsAccent2 : kSettingsDim,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      'Search settings',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
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
