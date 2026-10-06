import 'package:debrify/features/settings_widgets/presentation/settings_root_chrome.dart';
import 'package:debrify/features/settings_widgets/presentation/settings_rows.dart';
import 'package:debrify/features/settings_widgets/presentation/settings_tokens.dart';
import 'package:debrify/models/tv_render_quality.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/theme/app_focus.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_surface.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/utils/tv_reveal.dart';
import 'package:debrify/widgets/shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export 'package:debrify/features/settings_widgets/presentation/settings_links.dart'
    show launchSettingsUrl;
export 'package:debrify/features/settings_widgets/presentation/settings_page_chrome.dart'
    show
        SettingsBannerTone,
        SettingsInfoBanner,
        SettingsPageHeader,
        SettingsPageScaffold;
export 'package:debrify/features/settings_widgets/presentation/settings_page_theme.dart'
    show pushSettingsPage, settingsPageTheme, showSettingsDialog;
export 'package:debrify/features/settings_widgets/presentation/settings_pending_badge.dart'
    show WebDavSyncPendingBadge;
export 'package:debrify/features/settings_widgets/presentation/settings_root_chrome.dart'
    show SettingsBackground, SettingsHeader, SettingsSectionLabel;
export 'package:debrify/features/settings_widgets/presentation/settings_rows.dart'
    show SettingsRowContent, SettingsRows;
export 'package:debrify/features/settings_widgets/presentation/settings_tokens.dart'
    show
        kSettingsAccent,
        kSettingsAccent2,
        kSettingsAmber,
        kSettingsBg,
        kSettingsDim,
        kSettingsDim2,
        kSettingsGreen,
        kSettingsLine,
        kSettingsMaxWidth,
        kSettingsPanel,
        kSettingsPanel2,
        kSettingsRed;

/// Uniform monochrome initials chip for a connection provider ("RD", "JP").
/// Replaces the old per-provider colored gradient icon boxes — status is
/// carried by the dot/text instead, keeping the chrome calm like Stremio.
String settingsInitialsFor(String title) {
  final words = title
      .split(RegExp(r'[\s&]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.length >= 2) return (words[0][0] + words[1][0]).toUpperCase();
  if (words.isEmpty) return '?';
  // Single word: prefer internal capitals (AllDebrid → AD, PikPak → PP).
  final caps = words[0].replaceAll(RegExp(r'[^A-Z]'), '');
  if (caps.length >= 2) return caps.substring(0, 2);
  return words[0].length >= 2
      ? words[0].substring(0, 2).toUpperCase()
      : words[0].toUpperCase();
}

class ConnectionInfo {
  final String title;
  final bool connected;
  final String status;
  final String caption;
  final Future<void> Function() onTap;

  const ConnectionInfo({
    required this.title,
    required this.connected,
    required this.status,
    required this.caption,
    required this.onTap,
  });
}

/// Whether a configured connection is explicitly reporting a degraded state.
///
/// Providers use a few healthy labels (for example `Active` and `Configured`),
/// so treating every non-`Active` value as an error incorrectly marks Jackett
/// and Prowlarr as unhealthy. Only known negative states need intervention.
bool settingsConnectionNeedsAttention(ConnectionInfo info) {
  if (!info.connected) return false;
  final status = info.status.toLowerCase();
  return status.contains('inactive') ||
      status.contains('expired') ||
      status.contains('error') ||
      status.contains('failed') ||
      status.contains('attention');
}

bool settingsConnectionIsReady(ConnectionInfo info) =>
    info.connected && !settingsConnectionNeedsAttention(info);

class ConnectionsSummary extends StatefulWidget {
  final ConnectionInfo realDebrid;
  final ConnectionInfo torbox;
  final ConnectionInfo premiumize;
  final ConnectionInfo allDebrid;
  final ConnectionInfo pikpak;
  final ConnectionInfo webDav;
  final ConnectionInfo? mediaServers;
  final ConnectionInfo indexerManagers;
  final ConnectionInfo iptv;
  final ConnectionInfo trakt;
  final ConnectionInfo simkl;
  final ConnectionInfo tracking;
  // Null when MDBList is hidden (alpha) — its card + focus node are then omitted.
  final ConnectionInfo? mdblist;
  final FocusNode? firstCardFocusNode;

  const ConnectionsSummary({
    super.key,
    required this.realDebrid,
    required this.torbox,
    required this.premiumize,
    required this.allDebrid,
    required this.pikpak,
    required this.webDav,
    this.mediaServers,
    required this.indexerManagers,
    required this.iptv,
    required this.trakt,
    required this.simkl,
    required this.tracking,
    this.mdblist,
    this.firstCardFocusNode,
  });

  @override
  State<ConnectionsSummary> createState() => _ConnectionsSummaryState();
}

class _ConnectionsSummaryState extends State<ConnectionsSummary> {
  // Focus nodes for grid navigation
  // Layout (wide) — the Reddit card is hidden (source retired), its
  // ConnectionInfo/focus node are kept so nothing else has to change:
  // [realDebrid,  torbox]
  // [premiumize,  allDebrid]
  // [pikpak,      webDav]
  // [indexerManagers, iptv]
  // [tracking policy]      (full width)
  // [trakt,       simkl]
  // [mdblist]     (alone)
  late final FocusNode _torboxFocusNode;
  late final FocusNode _premiumizeFocusNode;
  late final FocusNode _allDebridFocusNode;
  late final FocusNode _pikpakFocusNode;
  late final FocusNode _webDavFocusNode;
  final FocusNode _mediaServersFocusNode = FocusNode(
    debugLabel: 'settings-media-servers',
  );
  late final FocusNode _indexerManagersFocusNode;
  late final FocusNode _iptvFocusNode;
  late final FocusNode _trackingFocusNode;
  late final FocusNode _traktFocusNode;
  late final FocusNode _simklFocusNode;
  late final FocusNode _mdblistFocusNode;

  @override
  void initState() {
    super.initState();
    _torboxFocusNode = FocusNode(debugLabel: 'settings-torbox');
    _premiumizeFocusNode = FocusNode(debugLabel: 'settings-premiumize');
    _allDebridFocusNode = FocusNode(debugLabel: 'settings-alldebrid');
    _pikpakFocusNode = FocusNode(debugLabel: 'settings-pikpak');
    _webDavFocusNode = FocusNode(debugLabel: 'settings-webdav');
    _indexerManagersFocusNode = FocusNode(
      debugLabel: 'settings-indexer-managers',
    );
    _iptvFocusNode = FocusNode(debugLabel: 'settings-iptv');
    _trackingFocusNode = FocusNode(debugLabel: 'settings-tracking');
    _traktFocusNode = FocusNode(debugLabel: 'settings-trakt');
    _simklFocusNode = FocusNode(debugLabel: 'settings-simkl');
    _mdblistFocusNode = FocusNode(debugLabel: 'settings-mdblist');
  }

  @override
  void dispose() {
    _torboxFocusNode.dispose();
    _premiumizeFocusNode.dispose();
    _allDebridFocusNode.dispose();
    _pikpakFocusNode.dispose();
    _webDavFocusNode.dispose();
    _mediaServersFocusNode.dispose();
    _indexerManagersFocusNode.dispose();
    _iptvFocusNode.dispose();
    _trackingFocusNode.dispose();
    _traktFocusNode.dispose();
    _simklFocusNode.dispose();
    _mdblistFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('Connections'),
        LayoutBuilder(
          builder: (context, constraints) {
            final bool wide = constraints.maxWidth > 520;
            final double itemWidth = wide
                ? (constraints.maxWidth - 10) / 2
                : constraints.maxWidth;
            // Grid layout (wide) — Reddit card hidden, source retired:
            // [RD]         [Torbox]
            // [Premiumize] [AllDebrid]
            // [PikPak]     [WebDAV]
            // [Indexers]   [IPTV]
            // ── Tracking ──
            // [cross-service policy]
            // ── Tracker services ──
            // [Trakt]       [Simkl]
            // [MDBList]
            //
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    // Row 1: Real Debrid (left), Torbox (right)
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.realDebrid,
                        focusNode: widget.firstCardFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _torboxFocusNode : null,
                        downNeighbor: wide
                            ? _premiumizeFocusNode
                            : _torboxFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.torbox,
                        focusNode: _torboxFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? widget.firstCardFocusNode : null,
                        upNeighbor: wide ? null : widget.firstCardFocusNode,
                        downNeighbor: wide
                            ? _allDebridFocusNode
                            : _premiumizeFocusNode,
                      ),
                    ),
                    // Row 2: Premiumize (left), AllDebrid (right)
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.premiumize,
                        focusNode: _premiumizeFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _allDebridFocusNode : null,
                        upNeighbor: wide
                            ? widget.firstCardFocusNode
                            : _torboxFocusNode,
                        downNeighbor: wide
                            ? _pikpakFocusNode
                            : _allDebridFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.allDebrid,
                        focusNode: _allDebridFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? _premiumizeFocusNode : null,
                        upNeighbor: wide
                            ? _torboxFocusNode
                            : _premiumizeFocusNode,
                        downNeighbor: wide
                            ? _webDavFocusNode
                            : _pikpakFocusNode,
                      ),
                    ),
                    // Row 3: PikPak (left), WebDAV (right)
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.pikpak,
                        focusNode: _pikpakFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _webDavFocusNode : null,
                        upNeighbor: wide
                            ? _premiumizeFocusNode
                            : _allDebridFocusNode,
                        downNeighbor: wide
                            ? _indexerManagersFocusNode
                            : _webDavFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.webDav,
                        focusNode: _webDavFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? _pikpakFocusNode : null,
                        upNeighbor: wide
                            ? _allDebridFocusNode
                            : _pikpakFocusNode,
                        downNeighbor: wide
                            ? _iptvFocusNode
                            : _indexerManagersFocusNode,
                      ),
                    ),
                    // Row 4: Indexer managers (left), IPTV (right).
                    // (The retired Reddit source's card, params and focus
                    // node were removed with its orphaned settings page.)
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.indexerManagers,
                        focusNode: _indexerManagersFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _iptvFocusNode : null,
                        upNeighbor: wide ? _pikpakFocusNode : _webDavFocusNode,
                        downNeighbor: wide
                            ? (widget.mediaServers != null
                                  ? _mediaServersFocusNode
                                  : _trackingFocusNode)
                            : _iptvFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.iptv,
                        focusNode: _iptvFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? _indexerManagersFocusNode : null,
                        upNeighbor: wide
                            ? _webDavFocusNode
                            : _indexerManagersFocusNode,
                        downNeighbor: widget.mediaServers != null
                            ? _mediaServersFocusNode
                            : _trackingFocusNode,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                if (widget.mediaServers != null) ...[
                  ConnectionCard(
                    info: widget.mediaServers!,
                    focusNode: _mediaServersFocusNode,
                    isLeftColumn: true,
                    upNeighbor: _iptvFocusNode,
                    downNeighbor: _trackingFocusNode,
                  ),
                  const SizedBox(height: 22),
                ],
                const SettingsSectionLabel('Tracking'),
                SizedBox(
                  width: constraints.maxWidth,
                  child: ConnectionCard(
                    info: widget.tracking,
                    focusNode: _trackingFocusNode,
                    isLeftColumn: true,
                    upNeighbor: widget.mediaServers != null
                        ? _mediaServersFocusNode
                        : wide
                        ? _indexerManagersFocusNode
                        : _iptvFocusNode,
                    downNeighbor: _traktFocusNode,
                  ),
                ),
                const SizedBox(height: 22),
                const SettingsSectionLabel('Tracker services'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    // Row 1: Trakt (left), Simkl (right).
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.trakt,
                        focusNode: _traktFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _simklFocusNode : null,
                        upNeighbor: _trackingFocusNode,
                        downNeighbor: wide && widget.mdblist != null
                            ? _mdblistFocusNode
                            : _simklFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.simkl,
                        focusNode: _simklFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? _traktFocusNode : null,
                        upNeighbor: wide ? _trackingFocusNode : _traktFocusNode,
                        downNeighbor: !wide && widget.mdblist != null
                            ? _mdblistFocusNode
                            : null,
                      ),
                    ),
                    // Row 2: MDBList (left, when enabled).
                    if (widget.mdblist != null)
                      SizedBox(
                        width: itemWidth,
                        child: ConnectionCard(
                          info: widget.mdblist!,
                          focusNode: _mdblistFocusNode,
                          isLeftColumn: true,
                          upNeighbor: wide ? _traktFocusNode : _simklFocusNode,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Flat provider row: mono initials chip · name + caption · status dot + text
/// · chevron. Focus/hover paints the accent ring, Stremio-style.
///
/// The manual DPAD neighbor wiring (and the sidebar hand-off on left from the
/// left column) is preserved verbatim from the original card — do not swap it
/// for default traversal without testing on real TV hardware.
class ConnectionCard extends StatefulWidget {
  final ConnectionInfo info;
  final FocusNode? focusNode;
  final bool isLeftColumn;
  final FocusNode? leftNeighbor;
  final FocusNode? rightNeighbor;
  final FocusNode? upNeighbor;
  final FocusNode? downNeighbor;

  const ConnectionCard({
    super.key,
    required this.info,
    this.focusNode,
    this.isLeftColumn = true,
    this.leftNeighbor,
    this.rightNeighbor,
    this.upNeighbor,
    this.downNeighbor,
  });

  @override
  State<ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<ConnectionCard> {
  /// The wrapper's own node, so focus can be read rather than remembered —
  /// see the note on `_SettingsTileState._focused`.
  final FocusNode _wrapNode = FocusNode(debugLabel: 'ConnectionCard');

  bool _hovered = false;

  /// Live, never cached. `hasFocus` is DESCENDANT-inclusive, so this wrapper
  /// reads true while the card's own InkWell below it holds focus — which is
  /// the intent, and the same value `Focus.onFocusChange` used to deliver.
  bool get _focused => _wrapNode.hasFocus;

  /// The theme's tempo, resolved in the one hook that may depend on inherited
  /// widgets and still re-runs when they change. The reveal below fires from a
  /// key handler, which is no place for a scope lookup.
  late AppMotion _motion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = AppMotion.of(context);
  }

  @override
  void dispose() {
    _wrapNode.dispose();
    super.dispose();
  }

  // Helper to focus and scroll into view
  void _focusAndScroll(FocusNode target) {
    target.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (target.context != null) {
        tvRevealMinimal(
          target.context!,
          duration: _motion.scaled(const Duration(milliseconds: 200)),
        );
      }
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (widget.leftNeighbor != null) {
        _focusAndScroll(widget.leftNeighbor!);
        return KeyEventResult.handled;
      } else if (widget.isLeftColumn && MainPageBridge.focusTvSidebar != null) {
        // Left column with no left neighbor: open sidebar
        MainPageBridge.focusTvSidebar!();
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (widget.rightNeighbor != null) {
        _focusAndScroll(widget.rightNeighbor!);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (widget.upNeighbor != null) {
        _focusAndScroll(widget.upNeighbor!);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (widget.downNeighbor != null) {
        _focusAndScroll(widget.downNeighbor!);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final info = widget.info;
    final bool active = settingsConnectionIsReady(info);
    // One color for both the dot and the status text so they can't disagree.
    final Color baseStateColor = info.connected
        ? (active ? t.success : t.danger)
        : t.dim2;
    final bool lit = _focused || _hovered;
    final bool spotlight = app.id == 'spotlight';
    final bool inverse =
        spotlight && lit && app.focus.expression == FocusExpression.parallax;
    final Color foreground = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final Color stateColor = inverse
        ? Color.lerp(baseStateColor, foreground, 0.42)!
        : baseStateColor;
    final radius = spotlight ? app.shape.br(13) : BorderRadius.circular(14);

    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Focus(
        focusNode: _wrapNode,
        onKeyEvent: _onKeyEvent,
        // hasFocus includes the InkWell child node, so this lights up when the
        // card's InkWell receives DPAD focus.
        onFocusChange: (_) => setState(() {}),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          // Plain Container (snap, no tween): animating a blurred BoxShadow
          // re-rasterizes per frame and janks weak TV GPUs (see
          // tv_sidebar_nav.dart for the same rule).
          child: Container(
            decoration: BoxDecoration(
              color: inverse
                  ? app.core.tx
                  : (lit
                        ? t.panel2
                        : spotlight
                        ? app.fade(app.core.tx, 0.047)
                        : t.panel),
              borderRadius: radius,
              border: Border.all(
                color: inverse ? app.core.tx : (_focused ? t.accent : t.line),
                width: 1,
              ),
              boxShadow: _focused && !inverse
                  ? [
                      BoxShadow(
                        color: t.accent.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                focusNode: widget.focusNode,
                borderRadius: radius,
                onTap: () async {
                  await info.onTap();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: inverse
                              ? foreground.withValues(alpha: 0.08)
                              : app.fade(
                                  app.core.tx,
                                  spotlight ? 0.065 : 0.055,
                                ),
                          borderRadius: app.shape.br(11),
                          border: Border.all(
                            color: inverse
                                ? foreground.withValues(alpha: 0.1)
                                : t.line,
                          ),
                        ),
                        child: Text(
                          settingsInitialsFor(info.title),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: inverse
                                ? foreground
                                : (lit ? t.accent2 : t.dim),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: spotlight
                                    ? foreground
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              info.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: inverse
                                    ? foreground.withValues(alpha: 0.5)
                                    : t.dim,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: stateColor,
                          shape: BoxShape.circle,
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: stateColor.withValues(alpha: 0.55),
                                    blurRadius: 7,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        info.status,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: stateColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: inverse
                            ? foreground.withValues(alpha: 0.42)
                            : t.dim2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flat panel section: quiet uppercase label above a bordered panel of rows
/// separated by hairlines.
class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Color? accentColor;

  /// One line under the header saying what the rows below have in common.
  ///
  /// Optional because most sections are self-evident from their title. It
  /// earns its place where a group's rows LOOK like their neighbours but
  /// answer a different question — Appearance's performance rows next to its
  /// style rows being the case that prompted it.
  final String? blurb;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.accentColor,
    this.blurb,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    // The `settingsGroup` family, and the reason it is capped to fill-or-rule:
    // this is ONE filled container whose rows have zero inter-row gap and an
    // in-place `Border.all`. Dropping both would shift every row by a pixel
    // and dissolve the grouping into an undifferentiated stack — so `space`
    // and `glass` are not on offer, and a look that asks for either is
    // clamped to `rule` by `modelFor` before it reaches here.
    final rule =
        app.surface.modelFor(SurfaceFamily.settingsGroup) ==
        SeparationModel.rule;
    final spotlight = app.id == 'spotlight';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) SettingsSectionLabel(title, color: accentColor),
        if (blurb != null)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10, right: 8),
            child: Text(
              blurb!,
              style: TextStyle(fontSize: 12, height: 1.4, color: t.dim),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            // A rule look keeps the border — that IS its separation — and
            // loses only the fill. The border width is unchanged either way,
            // which is what keeps the row geometry identical.
            color: rule
                ? Colors.transparent
                : spotlight
                ? app.fade(app.core.tx, app.isLight ? 0.035 : 0.047)
                : t.panel,
            borderRadius: spotlight
                ? app.shape.br(13)
                : BorderRadius.circular(16),
            border: Border.all(color: t.line, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  if (i != 0) Divider(height: 1, thickness: 1, color: t.line),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Prominent active-Look row used at the top of Appearance.
///
/// A Look changes several downstream controls at once, so presenting it as
/// one more 52dp row understated its effect and made Appearance read as an
/// arbitrary list. The swatches are derived from the active theme itself.
class SettingsLookHero extends StatefulWidget {
  const SettingsLookHero({
    super.key,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.focusNode,
  });

  final String label;
  final String subtitle;
  final Future<void> Function() onTap;
  final FocusNode? focusNode;

  @override
  State<SettingsLookHero> createState() => _SettingsLookHeroState();
}

class _SettingsLookHeroState extends State<SettingsLookHero> {
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  bool _hovered = false;

  /// Live, never cached — see the note on `_SettingsTileState._focused`.
  bool get _focused => _node.hasFocus;

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final lit = _focused || _hovered;
    final inverse = lit && app.focus.expression == FocusExpression.parallax;
    final foreground = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final radius = app.shape.br(13);
    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          focusNode: _node,
          onFocusChange: (_) => setState(() {}),
          onHover: (value) => setState(() => _hovered = value),
          onTap: () async => await widget.onTap(),
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 116),
            padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 18),
            decoration: BoxDecoration(
              color: inverse
                  ? app.core.tx
                  : Color.alphaBlend(
                      t.accent.withValues(alpha: 0.1),
                      app.fade(app.core.tx, 0.04),
                    ),
              borderRadius: radius,
              border: Border.all(
                color: inverse ? app.core.tx : t.accent.withValues(alpha: 0.24),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showSwatches = constraints.maxWidth >= 390;
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ACTIVE LOOK',
                            style: TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.55,
                              color: inverse
                                  ? foreground.withValues(alpha: 0.6)
                                  : t.accent2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              color: foreground,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            widget.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.4,
                              color: inverse
                                  ? foreground.withValues(alpha: 0.5)
                                  : t.dim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showSwatches) ...[
                      const SizedBox(width: 20),
                      _SettingsSwatches(inverse: inverse),
                    ],
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: inverse
                          ? foreground.withValues(alpha: 0.42)
                          : t.dim2,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSwatches extends StatelessWidget {
  const _SettingsSwatches({required this.inverse});

  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final colors = [
      app.core.ground,
      app.core.pane,
      app.settings.accent,
      app.core.tx,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < colors.length; i++) ...[
          Container(
            width: 25,
            height: 42,
            decoration: BoxDecoration(
              color: colors[i],
              borderRadius: app.shape.br(7),
              border: Border.all(
                color: inverse
                    ? app.inkOn(app.core.tx).withValues(alpha: 0.12)
                    : app.settings.line,
              ),
            ),
          ),
          if (i != colors.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// Flat settings row: mono icon · title + subtitle · chevron (or custom
/// trailing). Focus/hover lights the row with the accent ring so DPAD focus
/// is unmissable on TV.
class SettingsTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;
  final String? tag;
  final Widget? trailing;

  /// Renders the icon and title in the destructive red (Danger Zone).
  final bool destructive;

  /// False greys the whole row out and makes it inert: no tap, no hover
  /// light, and DPAD traversal skips it. The subtitle stays readable — a
  /// disabled row should say WHY it's disabled (e.g. "Only used by the
  /// Spotlight layout") rather than vanish.
  final bool enabled;

  /// Lets a parent (e.g. the TV two-pane rail) drive focus onto this row.
  final FocusNode? focusNode;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tag,
    this.trailing,
    this.destructive = false,
    this.enabled = true,
    this.focusNode,
  });

  /// Build from a shared [SettingsRowContent] so the TV and phone layouts
  /// stay in lockstep. [subtitle] overrides the content's (for dynamic rows
  /// like "Check for Updates").
  factory SettingsTile.spec(
    SettingsRowContent content, {
    Key? key,
    required Future<void> Function() onTap,
    String? subtitle,
    String? tag,
    Widget? trailing,
    bool destructive = false,
    bool enabled = true,
    FocusNode? focusNode,
  }) {
    return SettingsTile(
      key: key,
      icon: content.icon,
      title: content.title,
      subtitle: subtitle ?? content.subtitle,
      onTap: onTap,
      tag: tag,
      trailing: trailing,
      destructive: destructive,
      enabled: enabled,
      focusNode: focusNode,
    );
  }

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  /// Owned only when the caller did not supply one.
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  bool _hovered = false;

  /// Read LIVE from the node, never cached from `onFocusChange`.
  ///
  /// A cached bool is only as good as the callback that maintains it, and
  /// Flutter does not guarantee the falling edge: pop a route that was opened
  /// with OK and focus is restored to the MODAL SCOPE rather than to a row, so
  /// the rows that were focus-walked on the way in are never told they lost
  /// it. They keep their cached `true`, and under the Spotlight look that is
  /// not a faint stale highlight — every one of them paints a solid white
  /// plate, so the list comes back from a sub-page with two or three cursors
  /// on it and no way to tell which row OK will open.
  ///
  /// Derived state cannot go stale the way a remembered one does: the value is
  /// re-read on every build, so it is only ever as old as the last rebuild
  /// rather than as old as the last callback that arrived.
  ///
  /// Being precise about what that does and does not buy, because the
  /// difference matters if this is ever revisited: the repaint trigger is
  /// still the same `onFocusChange` the bug rides on, so a silently-missed
  /// notification leaves the WRONG PIXELS up until something rebuilds this
  /// row — it does not repaint it the instant focus leaves. What reliably
  /// rebuilds it is the row's own `onTap` being awaited below: callers
  /// setState when the pushed page returns, which rebuilds the list with
  /// fresh values. (A route transition alone would NOT do it — ModalScope
  /// caches the page subtree behind its AnimatedBuilder's `child`.)
  bool get _focused => _node.hasFocus;

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final spotlight = app.id == 'spotlight';
    final bool lit = widget.enabled && (_focused || _hovered);
    final bool inverse =
        spotlight && lit && app.focus.expression == FocusExpression.parallax;
    final Color foreground = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final Color iconColor = widget.destructive
        ? (inverse ? Color.lerp(t.danger, foreground, 0.38)! : t.danger)
        : (inverse ? foreground : (lit ? t.accent2 : t.dim));
    final radius = app.shape.br(12);
    // Snap, don't tween — per-keypress decoration lerps add cost on TV.
    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Container(
        decoration: BoxDecoration(
          color: inverse ? app.core.tx : (lit ? t.panel2 : Colors.transparent),
          borderRadius: radius,
          border: Border.all(
            color: inverse
                ? app.core.tx
                : (_focused ? t.accent : Colors.transparent),
            width: 1,
          ),
        ),
        child: InkWell(
          focusNode: _node,
          // Also drops the row out of DPAD traversal — an unfocusable node
          // never enters the traversal ring, so no remote step is eaten.
          canRequestFocus: widget.enabled,
          onFocusChange: (_) => setState(() {}),
          onHover: (h) => setState(() => _hovered = h),
          onTap: widget.enabled
              ? () async {
                  await widget.onTap();
                }
              : null,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            // One veil for the whole anatomy (icon, tag chip, chevron) rather
            // than per-part disabled colors that would drift out of sync.
            child: Opacity(
              opacity: widget.enabled ? 1 : 0.45,
              child: Row(
                children: [
                  if (spotlight)
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: inverse
                            ? foreground.withValues(alpha: 0.08)
                            : app.fade(app.core.tx, 0.055),
                        borderRadius: app.shape.br(10),
                      ),
                      child: Icon(widget.icon, color: iconColor, size: 20),
                    )
                  else
                    SizedBox(
                      width: 34,
                      child: Icon(widget.icon, color: iconColor, size: 22),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: widget.destructive
                                      ? t.danger
                                      : spotlight
                                      ? foreground
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            if (widget.tag != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: t.accent.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  widget.tag!,
                                  style: TextStyle(
                                    color: inverse
                                        ? Color.lerp(t.accent, foreground, 0.25)
                                        : t.accent2,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9.5,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: inverse
                                ? foreground.withValues(alpha: 0.5)
                                : t.dim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.trailing case final trailing?)
                    IconTheme.merge(
                      data: IconThemeData(
                        color: inverse
                            ? foreground.withValues(alpha: 0.42)
                            : t.dim2,
                      ),
                      child: trailing,
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: inverse
                          ? foreground.withValues(alpha: 0.42)
                          : t.dim2,
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

/// Flat toggle row — same anatomy as [SettingsTile] with a switch on the
/// right instead of a chevron.
class SettingsToggleTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final FocusNode? focusNode;
  final int subtitleMaxLines;

  const SettingsToggleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.focusNode,
    this.subtitleMaxLines = 1,
  });

  factory SettingsToggleTile.spec(
    SettingsRowContent content, {
    Key? key,
    required bool value,
    required ValueChanged<bool> onChanged,
    FocusNode? focusNode,
    int subtitleMaxLines = 1,
  }) {
    return SettingsToggleTile(
      key: key,
      icon: content.icon,
      title: content.title,
      subtitle: content.subtitle,
      value: value,
      onChanged: onChanged,
      focusNode: focusNode,
      subtitleMaxLines: subtitleMaxLines,
    );
  }

  @override
  State<SettingsToggleTile> createState() => _SettingsToggleTileState();
}

class _SettingsToggleTileState extends State<SettingsToggleTile> {
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  bool _hovered = false;

  /// Live, never cached — see the note on `_SettingsTileState._focused`.
  bool get _focused => _node.hasFocus;

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final spotlight = app.id == 'spotlight';
    final bool lit = _focused || _hovered;
    final bool inverse =
        spotlight && lit && app.focus.expression == FocusExpression.parallax;
    final foreground = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final radius = app.shape.br(12);
    // Snap, don't tween — per-keypress decoration lerps add cost on TV.
    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Container(
        decoration: BoxDecoration(
          color: inverse ? app.core.tx : (lit ? t.panel2 : Colors.transparent),
          borderRadius: radius,
          border: Border.all(
            color: inverse
                ? app.core.tx
                : (_focused ? t.accent : Colors.transparent),
            width: 1,
          ),
        ),
        child: InkWell(
          focusNode: _node,
          onFocusChange: (_) => setState(() {}),
          onHover: (h) => setState(() => _hovered = h),
          onTap: () => widget.onChanged(!widget.value),
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                if (spotlight)
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: inverse
                          ? foreground.withValues(alpha: 0.08)
                          : app.fade(app.core.tx, 0.055),
                      borderRadius: app.shape.br(10),
                    ),
                    child: Icon(
                      widget.icon,
                      color: inverse ? foreground : (lit ? t.accent2 : t.dim),
                      size: 20,
                    ),
                  )
                else
                  SizedBox(
                    width: 34,
                    child: Icon(
                      widget.icon,
                      color: lit ? t.accent2 : t.dim,
                      size: 22,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: spotlight
                              ? foreground
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        maxLines: widget.subtitleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: inverse
                              ? foreground.withValues(alpha: 0.5)
                              : t.dim,
                        ),
                      ),
                    ],
                  ),
                ),
                // The row's InkWell is the single DPAD stop; a focusable
                // Switch would make every toggle cost two presses on TV.
                ExcludeFocus(
                  child: Switch.adaptive(
                    value: widget.value,
                    onChanged: widget.onChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One Android TV "Screen Size" choice. [percent] is the share of the panel's
/// native density the UI is laid out at — smaller means a wider logical canvas,
/// so the same layouts draw smaller and more fits on screen. Values must stay in
/// step with `StorageService.kTvUiScaleOptions`; the shipped default is
/// `StorageService.kTvUiScaleDefault`.
///
/// Lives here (not in the TV settings shell) because two surfaces render it:
/// the TV Mode rail row's caption and the Screen Size page itself.
class TvUiScaleChoice {
  final int percent;
  final String title;
  final String subtitle;
  const TvUiScaleChoice(this.percent, this.title, this.subtitle);

  /// "Compact (80%)" — the row caption and the page's selected label.
  String get label => '$title ($percent%)';
}

const List<TvUiScaleChoice> kTvUiScaleChoices = [
  TvUiScaleChoice(100, 'Large', 'The original size — everything bigger'),
  TvUiScaleChoice(90, 'Medium', 'Default — about 10% more fits on screen'),
  TvUiScaleChoice(80, 'Compact', 'About 25% more fits on screen'),
];

/// Caption for [percent], falling back to the raw value if a stored size is
/// ever outside the offered set.
String tvUiScaleLabel(int percent) {
  for (final c in kTvUiScaleChoices) {
    if (c.percent == percent) return c.label;
  }
  return '$percent%';
}

/// One entry in the Android TV "Rendering" picker.
class TvRenderQualityChoice {
  final TvRenderQuality quality;
  final String label;
  final String subtitle;
  const TvRenderQualityChoice(this.quality, this.label, this.subtitle);
}

/// Automatic first: it's the default, and it's the only option that leaves the
/// device-capability call intact. The other two are named for the TRADE, not
/// for the mechanism — nobody browsing settings knows what a render buffer is,
/// but everybody knows which of "sharper" and "smoother" they want right now.
const List<TvRenderQualityChoice> kTvRenderQualityChoices = [
  TvRenderQualityChoice(
    TvRenderQuality.auto,
    'Automatic',
    "Default — Debrify picks based on this TV's graphics",
  ),
  TvRenderQualityChoice(
    TvRenderQuality.sharp,
    'Sharper picture',
    'Draw at the panel\'s full resolution',
  ),
  TvRenderQualityChoice(
    TvRenderQuality.fast,
    'Smoother navigation',
    'Draw at about 720p so scrolling stays fluid — text and art look softer',
  ),
];

/// Caption for [quality] — the settings row's subtitle and the picker's
/// selected label.
String tvRenderQualityLabel(TvRenderQuality quality) {
  for (final c in kTvRenderQualityChoices) {
    if (c.quality == quality) return c.label;
  }
  return 'Automatic';
}

/// One choice inside a [SettingsSelectDropdown].
class SettingsSelectOption {
  final String value;
  final String title;
  final String? subtitle;

  const SettingsSelectOption(this.value, this.title, [this.subtitle]);
}

/// Single-choice dropdown for settings cards — replaces the old
/// RadioListTile stacks (Post-Torrent Action, File Selection, …).
///
/// DPAD notes: the closed field is one focusable node (focus ring comes from
/// the themed `focusedBorder`); OK opens the menu, whose items take DPAD
/// focus natively, and BACK dismisses it. The selected option's subtitle is
/// echoed under the field so the descriptive copy isn't lost when closed.
class SettingsSelectDropdown extends StatelessWidget {
  final List<SettingsSelectOption> options;
  final String value;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  const SettingsSelectDropdown({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    final SettingsSelectOption? selected = options
        .cast<SettingsSelectOption?>()
        .firstWhere((o) => o!.value == value, orElse: () => null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          focusNode: focusNode,
          // A stale stored value (e.g. removed option) renders as an empty
          // field instead of tripping DropdownButton's value assert.
          initialValue: selected?.value,
          isExpanded: true,
          // Variable item heights so subtitles fit in the open menu.
          itemHeight: null,
          dropdownColor: t.panel2,
          borderRadius: BorderRadius.circular(14),
          // No focusColor: with an InputDecoration the SDK swaps the fill
          // color for it on focus, which would blank the panel fill. Focus
          // is carried by the themed focusedBorder instead.
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.dim),
          decoration: const InputDecoration(),
          // Explicit color (not inherit): the dropdown renders its menu items
          // with this style directly, outside the page's DefaultTextStyle.
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          // Closed field shows just the title; the subtitle lives below.
          selectedItemBuilder: (context) => [
            for (final o in options)
              Align(alignment: Alignment.centerLeft, child: Text(o.title)),
          ],
          items: [
            for (final o in options)
              DropdownMenuItem<String>(
                value: o.value,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        o.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: o.value == value
                              ? t.accent2
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (o.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          o.subtitle!,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: t.dim,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
        if (selected?.subtitle != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              selected!.subtitle!,
              style: TextStyle(fontSize: 11.5, height: 1.4, color: t.dim),
            ),
          ),
        ],
      ],
    );
  }
}

/// Non-interactive key/value row (e.g. Version).
class SettingsInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const SettingsInfoTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
  });

  factory SettingsInfoTile.spec(
    SettingsRowContent content, {
    Key? key,
    required String value,
  }) {
    return SettingsInfoTile(
      key: key,
      icon: content.icon,
      title: content.title,
      value: value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          SizedBox(width: 34, child: Icon(icon, color: t.dim, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              // No color: inherits onSurface (Text Brightness).
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: app.fade(app.core.tx, 0.05),
              borderRadius: app.shape.br(8),
              border: Border.all(color: t.line),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.dim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading skeleton, restyled to the flat Stremio panels.
class SettingsSkeleton extends StatelessWidget {
  const SettingsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsBackground(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SkeletonHeader(),
                SizedBox(height: 24),
                _SkeletonSection(),
                SizedBox(height: 24),
                _SkeletonSection(),
                SizedBox(height: 24),
                _SkeletonSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonHeader extends StatelessWidget {
  const _SkeletonHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Shimmer(width: 140, height: 24),
        SizedBox(height: 10),
        Shimmer(width: 220, height: 13),
      ],
    );
  }
}

class _SkeletonSection extends StatelessWidget {
  const _SkeletonSection();

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Shimmer(width: 120, height: 12),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.line),
          ),
          child: Column(
            children: [
              const _SkeletonTile(),
              Divider(height: 1, color: t.line),
              const _SkeletonTile(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: const [
          Shimmer(
            width: 34,
            height: 34,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          SizedBox(width: 12),
          Expanded(child: Shimmer(height: 14)),
        ],
      ),
    );
  }
}

/// The "why is this install in legacy mode" dialog, opened from the Profiles
/// row on every settings layout.
///
/// This dialog IS the bug report. The one channel a television reporter
/// reliably has is a phone photo of the screen, so the captured reason —
/// including the error and its first stack frame on the unpredicted path —
/// is shown in full here rather than summarized. The reassurance lines are
/// as load-bearing as the diagnosis: legacy mode looks like data loss from
/// the couch, and it is precisely the opposite.
Future<void> showLegacyModeInfoDialog(BuildContext context) {
  final app = AppThemeScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: app.sheetSurface,
      title: const Text('Running in legacy mode'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ProfileBootstrap.legacyReasonSummary,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: app.core.tx,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Your data is untouched — migration copies, never moves — and '
                'it retries automatically on every launch.\n\n'
                'If this keeps appearing, photograph this dialog and share it '
                'in the Discord: the text above identifies the cause.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: app.core.tx.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
