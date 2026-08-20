import 'package:flutter/material.dart';
import '../../utils/tv_reveal.dart';
import 'package:flutter/services.dart';

import '../../services/main_page_bridge.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../theme/app_focus.dart';
import '../../theme/widgets/parallax_focus.dart';
import 'settings_spotlight_shell.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

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
  final bool showSwitchProfile;
  final Future<void> Function()? onSwitchProfile;
  final Future<void> Function()? onAddProfile;
  final Future<void> Function()? onEditProfile;
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
  // Appearance rows. Labels caption the rows; every picker is its own page.
  final String textBrightnessLabel;
  final Future<void> Function() onOpenTextBrightness;
  final String launchAnimationLabel;
  final Future<void> Function() onOpenLaunchAnimation;
  // Screen size: percentage of the panel's native density the UI is laid out
  // at — 100 is the panel's own size, and smaller fits more on screen.
  final int tvUiScalePercent;
  final Future<void> Function() onOpenTvScreenSize;
  // Rendering: whether the UI is rastered at the panel's own resolution or at
  // a ~720p buffer the TV scales back up. Label, not enum — this file only
  // captions the row.
  final String tvRenderQualityLabel;
  final Future<void> Function() onOpenTvRenderQuality;
  final String tvHeroArtworkQualityLabel;
  final Future<void> Function() onOpenTvHeroArtworkQuality;
  final String tvSidebarStyleLabel;
  final Future<void> Function() onOpenTvSidebarStyle;
  final String discoverLayoutLabel;
  final Future<void> Function() onOpenDiscoverLayout;
  final String tvHomeStyleLabel;
  final Future<void> Function() onOpenTvHomeStyle;
  final String iptvStyleLabel;
  final Future<void> Function() onOpenIptvStyle;
  final String debrifyTvStyleLabel;
  final Future<void> Function() onOpenDebrifyTvStyle;
  final String playerGuideStyleLabel;
  final Future<void> Function() onOpenPlayerGuideStyle;
  final String detailPageStyleLabel;
  final Future<void> Function() onOpenDetailPageStyle;
  final String looksLabel;
  final Future<void> Function() onOpenLooks;
  final Future<void> Function() onOpenThemeTokens;
  final String themeTokensLabel;

  /// Withheld like [detailThemeLabel]: Theme Lab is a preview TOOL, not a
  /// setting — it changes nothing. Page and wiring stay.
  final Future<void> Function() onOpenThemeLab;
  final String appThemeLabel;
  final Future<void> Function() onOpenAppTheme;

  /// Still plumbed, deliberately: the Details Theme ROW is withheld from the
  /// Appearance list because App Theme write-through-mirrors into
  /// `detail_theme`, so two rows set the same thing and one silently
  /// overwrote the other. The page and its wiring stay so restoring the row is
  /// a few lines rather than an archaeology exercise — the same
  /// withheld-not-deleted pattern `kDetailThemesShipped` uses.
  final String detailThemeLabel;
  final Future<void> Function() onOpenDetailTheme;
  final String parentsGuideStyleLabel;
  final Future<void> Function() onOpenParentsGuideStyle;
  final String profileAppearanceLabel;
  final Future<void> Function() onOpenProfileAppearance;
  // Live TV & DVR.
  final Future<void> Function() onOpenRecordings;
  final Future<void> Function() onOpenIptvSettings;
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
    this.showSwitchProfile = false,
    this.onSwitchProfile,
    this.onAddProfile,
    this.onEditProfile,
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
    required this.textBrightnessLabel,
    required this.onOpenTextBrightness,
    required this.launchAnimationLabel,
    required this.onOpenLaunchAnimation,
    required this.tvUiScalePercent,
    required this.onOpenTvScreenSize,
    required this.tvRenderQualityLabel,
    required this.onOpenTvRenderQuality,
    required this.tvHeroArtworkQualityLabel,
    required this.onOpenTvHeroArtworkQuality,
    required this.tvSidebarStyleLabel,
    required this.onOpenTvSidebarStyle,
    required this.discoverLayoutLabel,
    required this.onOpenDiscoverLayout,
    required this.tvHomeStyleLabel,
    required this.onOpenTvHomeStyle,
    required this.iptvStyleLabel,
    required this.onOpenIptvStyle,
    required this.debrifyTvStyleLabel,
    required this.onOpenDebrifyTvStyle,
    required this.playerGuideStyleLabel,
    required this.onOpenPlayerGuideStyle,
    required this.detailPageStyleLabel,
    required this.onOpenDetailPageStyle,
    required this.looksLabel,
    required this.onOpenLooks,
    required this.onOpenThemeTokens,
    required this.themeTokensLabel,
    required this.onOpenThemeLab,
    required this.appThemeLabel,
    required this.onOpenAppTheme,
    required this.detailThemeLabel,
    required this.onOpenDetailTheme,
    required this.parentsGuideStyleLabel,
    required this.onOpenParentsGuideStyle,
    required this.profileAppearanceLabel,
    required this.onOpenProfileAppearance,
    required this.onOpenRecordings,
    required this.onOpenIptvSettings,
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
  final String title;
  final String description;
  const _Category(
    this.icon,
    this.label,
    this.subtitle,
    this.title,
    this.description,
  );
}

// ONE information architecture, shared verbatim with the phone layout and the
// search index — organized by what the user is changing, never by platform.
// Section names here MUST match _SettingsLayout's section titles and the
// search registrations in settings_screen.dart.
const List<_Category> _kCategories = [
  _Category(
    Icons.link_rounded,
    'Connections',
    'Debrid, cloud, IPTV & more',
    'Services, all in one place.',
    'See what is ready, what needs attention, and where playback will go.',
  ),
  _Category(
    Icons.sync_rounded,
    'Trackers',
    'Trakt & Simkl watch history',
    'Keep every watch in sync.',
    'Connect watch-history services and see their health at a glance.',
  ),
  _Category(
    Icons.home_rounded,
    'Home & Display',
    'Home screen rows & keyboard',
    'Shape the room you come home to.',
    'Arrange the home screen and tune this television for the room.',
  ),
  _Category(
    Icons.auto_awesome_rounded,
    'Appearance',
    'Text, home, sidebar, IPTV & player looks',
    'Make the interface feel like yours.',
    'A Look sets the room. Fine-tune only the controls that matter.',
  ),
  _Category(
    Icons.play_circle_outline_rounded,
    'Playback',
    'Player, skip segments, subtitles & audio',
    'Playback without surprises.',
    'Choose how videos start and what plays them on this television.',
  ),
  _Category(
    Icons.search_rounded,
    'Search',
    'Engines, filters & providers',
    'Find the right source faster.',
    'Engines, default filters, and provider routing form one pipeline.',
  ),
  _Category(
    Icons.fiber_dvr_rounded,
    'Live TV & DVR',
    'Debrify TV, recordings & IPTV',
    'Live television, organized.',
    'Manage channel sources, recordings, and the on-screen guide.',
  ),
  _Category(
    Icons.devices_rounded,
    'Devices',
    'Remote control & setup transfer',
    'Let your devices work together.',
    'Control another screen or move this setup without retyping it.',
  ),
  _Category(
    Icons.switch_account_rounded,
    'Profiles',
    'Who can use this device',
    'One device, many viewers.',
    'Switch between people, add someone new, and shape their access.',
  ),
  _Category(
    Icons.storage_rounded,
    'Data & Backup',
    'Downloads, backup & restore',
    'Your data, under your control.',
    'Manage stored state and keep a portable copy of your setup.',
  ),
  _Category(
    Icons.info_outline_rounded,
    'About',
    'Updates, version & community',
    'Debrify, up to date.',
    'Version, release checks, and the places where the community meets.',
  ),
  _Category(
    Icons.warning_amber_rounded,
    'Danger Zone',
    'Reset Debrify',
    'Start over, deliberately.',
    'Destructive actions stay isolated and explain what they remove.',
  ),
];

class _SettingsTvLayoutState extends State<SettingsTvLayout> {
  /// Max focusable rows in any single FIXED category — one whose rows are
  /// written out here rather than driven by a provider list (Appearance has
  /// exactly 16 — Looks from the theme work, Profile Picker, and Hero Artwork
  /// Quality from the
  /// player-dock merge, less Details Theme (App Theme covers it) and Theme Lab
  /// (a tool, not a setting); About has up to 6 with the conditional donation
  /// row;
  /// Data & Backup up to 5). Connections and Trackers are sized from their
  /// own lists; see the pool computation in [initState].
  ///
  /// MUST cover the largest category: the pane indexes [_paneNodes] directly,
  /// so a row added past the pool throws on build.
  /// Appearance is the longest fixed category. The pool must cover it, or the
  /// last row of that category has no node and cannot be reached.
  static const int _kMaxCategoryRows = 16;

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
    _focusPaneRow(0, travel: const Offset(1, 0));
  }

  void _focusPaneRow(int i, {Offset travel = Offset.zero}) {
    if (travel != Offset.zero) ParallaxTravel.note(travel);
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
      ParallaxTravel.note(const Offset(0, -1));
      // Above the first category sits the search item.
      if (index > 0) {
        _railNodes[index - 1].requestFocus();
      } else {
        _searchNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (index < _railNodes.length - 1) {
        ParallaxTravel.note(const Offset(0, 1));
        _railNodes[index + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _enterPane();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      // Always consume Left so focus never escapes the rail via directional
      // traversal, even if the sidebar hand-off isn't registered.
      ParallaxTravel.note(const Offset(-1, 0));
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
      ParallaxTravel.note(const Offset(0, 1));
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
      ParallaxTravel.note(const Offset(-1, 0));
      MainPageBridge.focusTvSidebar?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _paneKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final i = _paneNodes.indexWhere((n) => n.hasFocus);
    final grid =
        (_selected.value == 0 || _selected.value == 1) &&
        MediaQuery.sizeOf(context).width >= 880;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (grid && i > 0 && i.isOdd && _isPaneRowLive(i - 1)) {
        _focusPaneRow(i - 1, travel: const Offset(-1, 0));
        return KeyEventResult.handled;
      }
      // Return to the category we're viewing, not whichever rail item happens
      // to sit to the left geometrically.
      ParallaxTravel.note(const Offset(-1, 0));
      _railNodes[_selected.value].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (grid && i >= 0 && i.isEven && _isPaneRowLive(i + 1)) {
        _focusPaneRow(i + 1, travel: const Offset(1, 0));
      }
      // Nothing to the right of the pane — trap so focus can't escape.
      return KeyEventResult.handled;
    }
    // Hand-wire Up/Down between the pane's visible rows, trapping at the ends
    // so directional traversal can never bounce focus back onto the rail.
    // A pooled node is "in the current category" only if its context is
    // mounted — the pool is reused across categories and a FocusNode's context
    // is NOT nulled on unmount, so `context != null` would be a stale true for
    // a node last attached by a larger, previously-visited category.
    final step = grid ? 2 : 1;
    if (key == LogicalKeyboardKey.arrowUp) {
      if (i - step >= 0 && _isPaneRowLive(i - step)) {
        _focusPaneRow(i - step, travel: const Offset(0, -1));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (i >= 0 && i + step < _paneNodes.length && _isPaneRowLive(i + step)) {
        _focusPaneRow(i + step, travel: const Offset(0, 1));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Whether pane node [i] is attached to a row mounted in the current pane.
  bool _isPaneRowLive(int i) => _paneNodes[i].context?.mounted ?? false;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return SettingsBackground(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final railWidth = (constraints.maxWidth * 0.33).clamp(236.0, 320.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Invisible entry proxy: the parent State focuses
                // [firstFocusNode] on sidebar hand-off / logout restore;
                // [_onEntryFocus] redirects to the selected rail item.
                if (widget.firstFocusNode != null)
                  Focus(
                    focusNode: widget.firstFocusNode,
                    skipTraversal: true,
                    descendantsAreFocusable: false,
                    child: const SizedBox.shrink(),
                  ),
                _buildRail(railWidth),
                Container(width: 1, color: t.line),
                // Only the pane rebuilds when the category changes.
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _selected,
                          builder: (context, selected, _) =>
                              _buildPane(selected),
                        ),
                      ),
                      _buildFooter(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    Widget hint(String key, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: app.shape.br(5),
            border: Border.all(color: t.line),
          ),
          child: Text(
            key,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 8,
              color: t.dim,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(fontSize: 9, color: t.dim2)),
      ],
    );
    return Container(
      height: 46,
      margin: const EdgeInsets.only(right: 36),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showSaved = constraints.maxWidth >= 650;
          return Row(
            children: [
              const SizedBox(width: 32),
              hint('←', 'categories'),
              const SizedBox(width: 17),
              hint('↑ ↓', 'move'),
              const SizedBox(width: 17),
              hint('OK', 'open'),
              if (showSaved) ...[
                const Spacer(),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.success,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  'Changes save automatically',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 8,
                    color: t.success.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildRail(double width) {
    return SizedBox(
      width: width,
      child: SingleChildScrollView(
        controller: _railScroll,
        padding: const EdgeInsets.fromLTRB(24, 28, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 12, right: 8, bottom: 20),
              child: SettingsRootHeader(compact: true),
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
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              key: ValueKey<int>(selected),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _kCategories[selected].label.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: selected == 10
                              ? AppThemeScope.of(context).settings.danger
                              : AppThemeScope.of(
                                  context,
                                ).settings.accent.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _kCategories[selected].title,
                        style: const TextStyle(
                          fontSize: 28,
                          height: 1.06,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.7,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Text(
                          _kCategories[selected].description,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: AppThemeScope.of(context).settings.dim,
                          ),
                        ),
                      ),
                    ],
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
        return [_buildConnectionGrid(widget.connections)];
      case 1: // Trackers
        return [_buildConnectionGrid(widget.trackers)];
      case 2: // Home & Display
        // Nodes stay CONTIGUOUS from 0 — the DPAD walker only advances to
        // the immediately adjacent live node, so a gap strands Down.
        return [
          SettingsSection(
            title: '',
            children: [
              SettingsTile.spec(
                SettingsRows.homePage,
                onTap: widget.onOpenHomePageSettings,
                focusNode: _paneNodes[0],
              ),
              SettingsToggleTile.spec(
                SettingsRows.tvKeyboard,
                value: widget.tvKeyboardEnabled,
                onChanged: widget.onToggleTvKeyboard,
                focusNode: _paneNodes[1],
              ),
            ],
          ),
        ];
      case 3: // Appearance — grouped by the QUESTION each row answers.
        // Four groups, not one list of fifteen. The rows used to interleave
        // four different kinds of decision — a global theme, a per-screen
        // layout, a per-device performance cap and a preset that sets several
        // of the others — which is what made the category read as noise.
        //
        // `_paneNodes` is indexed POSITIONALLY and `_paneKey` wires Up/Down as
        // index ± 1, so the numbering has to stay contiguous across the group
        // boundaries: 0..15 top to bottom, headers excluded. Section headers
        // are plain text and take no focus, so DPAD steps over them.
        return [
          SettingsLookHero(
            label: widget.looksLabel,
            subtitle: 'Full-bleed art, borderless focus, and ambient detail.',
            onTap: widget.onOpenLooks,
            focusNode: _paneNodes[0],
          ),
          const SizedBox(height: 18),
          SettingsSection(
            title: 'Presets',
            blurb:
                'One pick that sets the theme, layouts and launch '
                'animation together.',
            children: [
              SettingsTile.spec(
                SettingsRows.themeTokens,
                subtitle: widget.themeTokensLabel,
                onTap: widget.onOpenThemeTokens,
                focusNode: _paneNodes[1],
              ),
            ],
          ),
          const SizedBox(height: 18),
          // The App Theme row is gone: a Look is the single top-level choice
          // now, and Advanced under it edits the individual tokens. The rows
          // below were RENUMBERED rather than left with a hole — the pane
          // indexes `_paneNodes` directly and a test asserts the indices are
          // contiguous from zero, because a gap is a row the remote skips.
          SettingsSection(
            title: 'Theme',
            blurb: 'Colour, focus and motion. Applies everywhere in the app.',
            children: [
              SettingsTile.spec(
                SettingsRows.textBrightness,
                subtitle: widget.textBrightnessLabel,
                onTap: widget.onOpenTextBrightness,
                focusNode: _paneNodes[2],
              ),
              SettingsTile.spec(
                SettingsRows.launchAnimation,
                subtitle: widget.launchAnimationLabel,
                onTap: widget.onOpenLaunchAnimation,
                focusNode: _paneNodes[3],
              ),
            ],
          ),
          const SizedBox(height: 18),
          SettingsSection(
            title: 'Screen layouts',
            blurb: 'Where things sit. Each screen is chosen separately.',
            children: [
              SettingsTile.spec(
                SettingsRows.tvHomeStyle,
                subtitle: widget.tvHomeStyleLabel,
                onTap: widget.onOpenTvHomeStyle,
                focusNode: _paneNodes[4],
              ),
              SettingsTile.spec(
                SettingsRows.discoverLayout,
                subtitle: widget.discoverLayoutLabel,
                onTap: widget.onOpenDiscoverLayout,
                focusNode: _paneNodes[5],
              ),
              SettingsTile.spec(
                SettingsRows.detailPageStyle,
                subtitle: widget.detailPageStyleLabel,
                onTap: widget.onOpenDetailPageStyle,
                focusNode: _paneNodes[6],
              ),
              SettingsTile.spec(
                SettingsRows.tvSidebarStyle,
                subtitle: widget.tvSidebarStyleLabel,
                onTap: widget.onOpenTvSidebarStyle,
                focusNode: _paneNodes[7],
              ),
              SettingsTile.spec(
                SettingsRows.iptvAppearance,
                subtitle: widget.iptvStyleLabel,
                onTap: widget.onOpenIptvStyle,
                focusNode: _paneNodes[8],
              ),
              SettingsTile.spec(
                SettingsRows.debrifyTvAppearance,
                subtitle: widget.debrifyTvStyleLabel,
                onTap: widget.onOpenDebrifyTvStyle,
                focusNode: _paneNodes[9],
              ),
              SettingsTile.spec(
                SettingsRows.playerGuideStyle,
                subtitle: widget.playerGuideStyleLabel,
                onTap: widget.onOpenPlayerGuideStyle,
                focusNode: _paneNodes[10],
              ),
              SettingsTile.spec(
                SettingsRows.parentsGuideStyle,
                subtitle: widget.parentsGuideStyleLabel,
                onTap: widget.onOpenParentsGuideStyle,
                focusNode: _paneNodes[11],
              ),
              SettingsTile.spec(
                SettingsRows.profileAppearance,
                subtitle: widget.profileAppearanceLabel,
                onTap: widget.onOpenProfileAppearance,
                focusNode: _paneNodes[12],
              ),
            ],
          ),
          const SizedBox(height: 18),
          SettingsSection(
            title: 'Display',
            blurb:
                'How this device draws. These affect performance, not '
                'style.',
            children: [
              SettingsTile.spec(
                SettingsRows.tvScreenSize,
                subtitle: tvUiScaleLabel(widget.tvUiScalePercent),
                onTap: widget.onOpenTvScreenSize,
                focusNode: _paneNodes[13],
              ),
              SettingsTile.spec(
                SettingsRows.tvRenderQuality,
                subtitle: widget.tvRenderQualityLabel,
                onTap: widget.onOpenTvRenderQuality,
                focusNode: _paneNodes[14],
              ),
              SettingsTile.spec(
                SettingsRows.tvHeroArtworkQuality,
                subtitle: widget.tvHeroArtworkQualityLabel,
                onTap: widget.onOpenTvHeroArtworkQuality,
                focusNode: _paneNodes[15],
              ),
            ],
          ),
        ];
      case 4: // Playback
        return [
          SettingsSection(
            title: '',
            children: [
              SettingsTile.spec(
                SettingsRows.player,
                onTap: widget.onOpenExternalPlayerSettings,
                focusNode: _paneNodes[0],
              ),
            ],
          ),
        ];
      case 5: // Search
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
      case 6: // Live TV & DVR
        return [
          SettingsSection(
            title: '',
            children: [
              SettingsTile.spec(
                SettingsRows.debrifyTv,
                onTap: widget.onOpenDebrifyTvSettings,
                focusNode: _paneNodes[0],
              ),
              SettingsTile.spec(
                SettingsRows.recordings,
                onTap: widget.onOpenRecordings,
                focusNode: _paneNodes[1],
              ),
              SettingsTile.spec(
                SettingsRows.iptvPlaylists,
                onTap: widget.onOpenIptvSettings,
                focusNode: _paneNodes[2],
              ),
            ],
          ),
        ];
      case 7: // Devices
        return [
          SettingsSection(
            title: '',
            children: [
              SettingsTile.spec(
                SettingsRows.remote,
                onTap: () async => widget.onOpenRemoteControl(),
                focusNode: _paneNodes[0],
              ),
            ],
          ),
        ];
      case 8: // Profiles — its own card (it was a tenant row under Devices).
        return [
          SettingsSection(
            title: '',
            children: [
              if (widget.showSwitchProfile) ...[
                SettingsTile.spec(
                  SettingsRows.switchProfile,
                  onTap: widget.onSwitchProfile ?? () async {},
                  focusNode: _paneNodes[0],
                ),
                SettingsTile.spec(
                  SettingsRows.addProfile,
                  onTap: widget.onAddProfile ?? () async {},
                  focusNode: _paneNodes[1],
                ),
                SettingsTile.spec(
                  SettingsRows.editProfile,
                  onTap: widget.onEditProfile ?? () async {},
                  focusNode: _paneNodes[2],
                ),
              ] else
                // Legacy-mode installs keep the card but say why it's empty
                // rather than presenting actions that would fail — and OK
                // opens the full captured reason, because a photo of that
                // dialog is the whole bug report a TV user can give.
                SettingsTile.spec(
                  SettingsRowContent(
                    icon: Icons.info_outline_rounded,
                    title: 'Profiles unavailable',
                    // First line only: the reason's second line can be a
                    // stack frame, and the row is one-line copy.
                    subtitle:
                        ProfileBootstrap.legacyReasonSummary.split('\n').first,
                  ),
                  onTap: () => showLegacyModeInfoDialog(context),
                  focusNode: _paneNodes[0],
                ),
            ],
          ),
        ];
      case 9: // Data & Backup
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
      case 10: // About (Updates + Support merged — matches the phone layout)
        {
          // The donation row is conditional, so index the pane nodes off a
          // running counter to keep Up/Down wiring contiguous.
          int p = 0;
          return [
            const SettingsSectionLabel('Updates'),
            SettingsSection(
              title: '',
              children: [
                SettingsToggleTile.spec(
                  SettingsRows.autoUpdate,
                  value: widget.autoUpdateChecksEnabled,
                  onChanged: widget.onToggleAutoUpdateChecks,
                  focusNode: _paneNodes[p++],
                ),
                SettingsTile.spec(
                  SettingsRows.checkUpdates,
                  subtitle: widget.updateSubtitle,
                  onTap: widget.onCheckForUpdates,
                  tag: 'New',
                  focusNode: _paneNodes[p++],
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
            const SizedBox(height: 18),
            const SettingsSectionLabel('Community & Support'),
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
        }
      case 11: // Danger Zone
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

  Widget _buildConnectionGrid(List<ConnectionInfo> connections) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = MediaQuery.sizeOf(context).width >= 880;
        final width = twoColumns
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < connections.length; i++)
              SizedBox(
                width: width,
                child: ConnectionCard(
                  info: connections[i],
                  focusNode: _paneNodes[i],
                  isLeftColumn: false,
                ),
              ),
          ],
        );
      },
    );
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
  /// Live, never cached — a remembered flag survives the focus change it
  /// missed. See the note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  bool get _focused => widget.focusNode.hasFocus;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final inverse =
        _focused && app.focus.expression == FocusExpression.parallax;
    final focusInk = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final radius = app.shape.br(11);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ParallaxFocus(
        focused: _focused,
        shape: ParallaxShape.settingsRow,
        radius: radius,
        child: Focus(
          // Key handler only — the InkWell below owns the focusable node, so
          // this wrapper must not be a focus target itself.
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) => widget.onKey(node, event, widget.index),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              focusNode: widget.focusNode,
              borderRadius: radius,
              onTap: widget.onActivate,
              onFocusChange: (f) {
                setState(() {});
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
                  final Color fg = inverse
                      ? focusInk
                      : (focused || selected)
                      ? app.core.tx
                      : t.dim;
                  final Color iconColor = inverse
                      ? focusInk
                      : (focused || selected)
                      ? t.accent2
                      : t.dim;
                  // Subtitle brightens with the row but stays a step dimmer than
                  // the title so the label still reads as primary.
                  final Color subColor = inverse
                      ? focusInk.withValues(alpha: 0.52)
                      : (focused || selected)
                      ? app.fade(app.core.tx, 0.60)
                      : t.dim2;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: inverse
                          ? app.core.tx
                          : selected
                          ? app.fade(app.core.tx, 0.1)
                          : (focused ? t.panel2 : Colors.transparent),
                      borderRadius: radius,
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
  /// Live, never cached — a remembered flag survives the focus change it
  /// missed. See the note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  bool get _focused => widget.focusNode.hasFocus;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final bool focused = _focused;
    final inverse = focused && app.focus.expression == FocusExpression.parallax;
    final Color fg = inverse
        ? app.inkOn(app.core.tx)
        : focused
        ? app.core.tx
        : t.dim;
    final radius = app.shape.br(22);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ParallaxFocus(
        focused: focused,
        shape: ParallaxShape.settingsRow,
        radius: radius,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: widget.onKey,
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              focusNode: widget.focusNode,
              borderRadius: radius,
              onTap: widget.onActivate,
              onFocusChange: (f) {
                setState(() {});
                if (f) {
                  // Reveal the top of the rail (search sits above category 0).
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && context.mounted) tvRevealMinimal(context);
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: inverse
                      ? app.core.tx
                      : (focused ? t.panel2 : app.fade(app.core.tx, 0.07)),
                  borderRadius: radius,
                  border: Border.all(
                    color: inverse
                        ? app.core.tx
                        : (focused ? t.accent : t.line),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: inverse ? fg : (focused ? t.accent2 : t.dim),
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
      ),
    );
  }
}
