import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../../services/iptv_media_store.dart' show IptvListMeta;
import '../../theme/app_theme_scope.dart';
import '../../utils/tv_keys.dart';
import 'iptv_stage_panel.dart' show IptvMonogram;
import 'styles/iptv_style.dart';

/// The Command Center's left rail: every destination on one column —
/// LIBRARY (Favorites · Continue · Recordings), SOURCES (playlists with
/// counts), LISTS (the user's own), and a Manage footer.
///
/// DPAD contract: items are plain focusables, so geometry does the work —
/// LEFT from the channel grid's first column lands here, LEFT from here has
/// no candidate and bubbles to the shell's global action (the app sidebar,
/// preserving the LEFT-only policy with zero interception code). UP/DOWN
/// walk the column, RIGHT walks into the guide, and OK selects.
///
/// Perf: a static column — no per-frame work, counts are precomputed by the
/// caller once per playlist load, and selection state is a plain rebuild.
class IptvCommandRail extends StatelessWidget {
  final List<IptvPlaylist> playlists;
  final IptvPlaylist? selectedPlaylist;
  final List<IptvListMeta> customLists;

  /// playlist.id → channel count (real sources only), precomputed.
  final Map<String, int> sourceCounts;
  final int favoritesCount;
  final int scheduledCount;

  /// False hides the Recordings entry entirely — recording disabled or
  /// unsupported must not advertise a DVR that would refuse to work
  /// (settings hides its recordings row in the same state).
  final bool showScheduled;

  /// True while the recording engine is capturing — the Recordings entry
  /// wears a live dot. (Optional; false hides it.)
  final bool recordingActive;

  final ValueChanged<IptvPlaylist> onSelectPlaylist;
  final VoidCallback onOpenScheduled;
  final VoidCallback onManageSources;

  /// Styled-look tokens ('edition'/'console'), or null for the shipped
  /// Command Center paint. Behavior — focus wiring, swallow flags, counts,
  /// selection — is IDENTICAL in every style; only paint branches on this.
  final IptvStyleTokens? tokens;

  const IptvCommandRail({
    super.key,
    required this.playlists,
    required this.selectedPlaylist,
    required this.customLists,
    required this.sourceCounts,
    required this.favoritesCount,
    required this.scheduledCount,
    required this.onSelectPlaylist,
    required this.onOpenScheduled,
    required this.onManageSources,
    this.showScheduled = true,
    this.recordingActive = false,
    this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final favorites = playlists.where((p) => p.isFavorites).toList();
    final continueWatching = playlists
        .where((p) => p.isContinueWatching)
        .toList();
    final sources = playlists.where((p) => !p.isVirtual).toList();
    final addonSources = playlists.where((p) => p.isStremioAddon).toList();
    final listPlaylists = playlists.where((p) => p.isCustomList).toList();

    final t = tokens;
    return Container(
      width: 196,
      decoration: t == null
          ? BoxDecoration(
              // The cockpit's recessed ground — `iptv.stageBg` names the
              // command rail as one of its three surfaces, so the rail follows
              // the page's own recess instead of a fixed navy that read
              // dark-on-dark against the derived ink below it.
              //
              // Legacy keeps its literal: it paints the rail a step DEEPER
              // than the stage (#080B18 vs stageBg's #0B0914) and no token
              // carries that value, so pinning it is the only way the shipped
              // pixel survives while every other theme still flips.
              color:
                  app.iptv.railBg.withValues(alpha: 0.65),
              border: Border(
                right: BorderSide(color: app.core.tx.withValues(alpha: 0.07)),
              ),
            )
          : BoxDecoration(
              // Each pane paints its OWN background — a page-wide sheet would
              // sit under the stage's punched underlay hole in an ancestor
              // layer and block the live video (see _buildTvTwoPane).
              color: t.bg,
              border: Border(right: BorderSide(color: t.hairline)),
            ),
      child: FocusTraversalGroup(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
          children: [
            _RailHeader('LIBRARY', tokens: t, first: true),
            for (final p in favorites)
              _RailItem(
                tokens: t,
                icon: Icons.star_rounded,
                iconColor: const Color(0xFFF5C042),
                label: 'Favorites',
                count: favoritesCount,
                selected: selectedPlaylist?.id == p.id,
                // Top focus edge of the rail: UP stays here instead of
                // leaking into whichever pane sits upper-right.
                swallowUp: true,
                onSelect: () => onSelectPlaylist(p),
              ),
            for (final p in continueWatching)
              _RailItem(
                tokens: t,
                icon: Icons.history_rounded,
                label: 'Continue',
                selected: selectedPlaylist?.id == p.id,
                onSelect: () => onSelectPlaylist(p),
              ),
            if (showScheduled)
              _RailItem(
                tokens: t,
                icon: Icons.fiber_manual_record_rounded,
                iconColor: app.iptv.recordAccent,
                label: 'Recordings',
                count: scheduledCount,
                selected: false,
                chevron: true,
                liveDot: recordingActive,
                onSelect: onOpenScheduled,
              ),
            _RailHeader('SOURCES', tokens: t),
            for (final p in sources)
              _RailItem(
                tokens: t,
                mark: t == null ? IptvMonogram(name: p.name, size: 24) : null,
                label: p.name,
                count: sourceCounts[p.id],
                selected: selectedPlaylist?.id == p.id,
                onSelect: () => onSelectPlaylist(p),
              ),
            if (addonSources.isNotEmpty) ...[
              _RailHeader('ADDONS', tokens: t),
              for (final p in addonSources)
                _RailItem(
                  tokens: t,
                  icon: Icons.extension_rounded,
                  label: p.name,
                  selected: selectedPlaylist?.id == p.id,
                  onSelect: () => onSelectPlaylist(p),
                ),
            ],
            if (listPlaylists.isNotEmpty) ...[
              _RailHeader('LISTS', tokens: t),
              for (final p in listPlaylists)
                _RailItem(
                  tokens: t,
                  icon: Icons.bookmark_rounded,
                  label: p.name,
                  count: _listCount(p),
                  selected: selectedPlaylist?.id == p.id,
                  onSelect: () => onSelectPlaylist(p),
                ),
            ],
            // The Manage footer is its own section too — rule it off from
            // whatever list ends above it.
            Container(
              height: 1,
              margin: const EdgeInsets.fromLTRB(10, 14, 10, 10),
              color: t?.hairline ?? app.iptv.hairline,
            ),
            _RailItem(
              tokens: t,
              icon: Icons.tune_rounded,
              label: 'Manage sources',
              selected: false,
              chevron: true,
              // Bottom focus edge — DOWN stops here.
              swallowDown: true,
              onSelect: onManageSources,
            ),
          ],
        ),
      ),
    );
  }

  int? _listCount(IptvPlaylist listPlaylist) {
    for (final meta in customLists) {
      if (listPlaylist.id == 'iptv-list-${meta.id}') return meta.channelCount;
    }
    return null;
  }
}

/// Section heading: a hairline rule (skipped on the first section) over a
/// bold small-caps title, so the rail reads as titled groups rather than one
/// undifferentiated list. Same treatment in every style, in each style's own
/// palette (user-requested — this deliberately updates the command look too).
class _RailHeader extends StatelessWidget {
  final String text;
  final IptvStyleTokens? tokens;

  /// First section: no divider above (nothing to separate from).
  final bool first;

  const _RailHeader(this.text, {this.tokens, this.first = false});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!first)
          Container(
            height: 1,
            margin: const EdgeInsets.fromLTRB(10, 14, 10, 0),
            color: t?.hairline ?? app.iptv.hairline,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
          child: Text(
            text,
            style: t == null
                ? TextStyle(
                    color: app.iptv.inkDim,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  )
                : TextStyle(
                    color: t.fgDim,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.4,
                    fontFamily: t.monoFamily.isEmpty ? null : t.monoFamily,
                  ),
          ),
        ),
      ],
    );
  }
}

class _RailItem extends StatefulWidget {
  final IconData? icon;
  final Color? iconColor;
  final Widget? mark;
  final String label;
  final int? count;
  final bool selected;
  final bool chevron;
  final bool liveDot;
  final bool swallowUp;
  final bool swallowDown;
  final VoidCallback onSelect;
  final IptvStyleTokens? tokens;

  const _RailItem({
    this.icon,
    this.iconColor,
    this.mark,
    required this.label,
    this.count,
    required this.selected,
    this.chevron = false,
    this.liveDot = false,
    this.swallowUp = false,
    this.swallowDown = false,
    required this.onSelect,
    this.tokens,
  });

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    // The rail's own focus gold: NOT home.focus (#FBBF24) — a different
    // literal, so no token can carry it without shifting the cursor's colour.
    const gold = Color(0xFFF5C042);
    final row = widget.tokens != null
        ? _styledRow(widget.tokens!)
        : Container(
            height: 36,
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color: widget.selected
                  ? app.iptv.railSelectionFill
                  : _focused
                  ? app.core.tx.withValues(alpha: 0.05)
                  : Colors.transparent,
              border: Border.all(
                color: _focused ? gold : Colors.transparent,
                width: 1.8,
              ),
            ),
            child: Row(
              children: [
                if (widget.mark != null)
                  widget.mark!
                else
                  Icon(
                    widget.icon,
                    size: 16,
                    color:
                        widget.iconColor ??
                        app.core.tx.withValues(
                          alpha: widget.selected ? 0.9 : 0.55,
                        ),
                  ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.selected
                          // Ink on the selection FILL (a 16% violet tint over
                          // the rail's ground), so it is scored rather than
                          // taken from the page: now that the ground follows
                          // the theme, legacy's near-white would disappear on
                          // a paper rail. Legacy keeps its own literal, so the
                          // shipped pixel is unchanged.
                          ? app.iptv.railFocusInk
                          : app.core.tx.withValues(alpha: 0.72),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.liveDot)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(left: 5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: app.iptv.recordAccent,
                    ),
                  )
                else if (widget.count != null)
                  Text(
                    _fmtCount(widget.count!),
                    style: TextStyle(
                      color: app.core.tx.withValues(alpha: 0.34),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  )
                else if (widget.chevron)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 15,
                    color: app.core.tx.withValues(alpha: 0.3),
                  ),
              ],
            ),
          );

    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        // OK selects; RIGHT does NOT. Arrows move, the centre button acts —
        // the 10-foot contract everywhere else in the app. RIGHT used to
        // select as the rail's only escape hatch (it swallowed the key, so
        // traversal could never leave), which meant merely walking toward
        // the guide silently switched source. Now it just walks: the guide
        // it lands on is the one still selected, so nothing can mismatch.
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        // Vertical containment at the rail's edges — never leak into the
        // panes to the right.
        if (widget.swallowUp &&
            event.logicalKey == LogicalKeyboardKey.arrowUp) {
          return KeyEventResult.handled;
        }
        if (widget.swallowDown &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        behavior: HitTestBehavior.opaque,
        child: row,
      ),
    );
  }

  /// The styled (edition/console) row paint: text-first — no leading icons,
  /// no filled selection pill, no gold ring. Focus = a 2px rule on the left
  /// edge (paper for edition, amber for console) + a faint tint; selection =
  /// full-strength text. Same height/behavior as the legacy row.
  Widget _styledRow(IptvStyleTokens t) {
    final mono = t.monoFamily.isEmpty ? null : t.monoFamily;
    return Container(
      height: 36,
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: _focused ? t.focusTint : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: _focused ? t.accent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: (widget.selected || _focused) ? t.fg : t.fgDim,
                fontSize: 12.5,
                fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (widget.liveDot)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(left: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.rec,
                boxShadow: [
                  BoxShadow(color: t.rec.withValues(alpha: 0.6), blurRadius: 8),
                ],
              ),
            )
          else if (widget.count != null)
            Text(
              _fmtCount(widget.count!),
              style: TextStyle(
                color: t.fgFaint,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                fontFamily: mono,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          else if (widget.chevron)
            Icon(Icons.chevron_right_rounded, size: 15, color: t.fgFaint),
        ],
      ),
    );
  }

  String _fmtCount(int n) {
    if (n >= 10000) return '${(n / 1000).round()}k';
    if (n >= 1000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k >= 9.95 ? 0 : 1)}k';
    }
    return '$n';
  }
}
