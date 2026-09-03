import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme_scope.dart';
import '../theme/widgets/focus_expression.dart';
import '../utils/format_tag_detector.dart';
import '../utils/tv_keys.dart';
import 'format_badge.dart';
import 'stream_badge_strip.dart';

/// The unified row for the redesigned Sources page. Drives two looks from one
/// widget:
///
///  * **Format row (Concept F)** — pass [formatTags]; the row shows the title,
///    a `source · resolution · size · ↑seeders · provider` [subtitle], the
///    ⚡ cache pill, coverage/stream badges, and a wrap of [FormatBadge] logos.
///  * **Compact row (keyword / list)** — leave [formatTags] empty and pass a
///    [qualityTag]; the format-logo wrap collapses to nothing.
///
/// Quiet palette everywhere except the format logos: one purple accent for
/// focus, one green for cache, white at varying opacity for the rest. DPAD
/// key-handling mirrors the existing `TorrentResultRow` (SELECT = tap, 500ms
/// SELECT = long-press, ↑/↓ = navigate) so focus behaviour stays identical.
class SourceRow extends StatefulWidget {
  const SourceRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.focusNode,
    required this.onTap,
    this.formatTags = const [],
    this.badgeName,
    this.badgeDescription,
    this.qualityTag,
    this.cacheLabel,
    this.coverageBadge,
    this.streamBadge,
    this.isTelevision = false,
    this.showPlayPill = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onCopy,
    this.titleMaxLines,
    this.onLongPress,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  final String title;
  final String subtitle;
  final FocusNode focusNode;
  final VoidCallback onTap;

  /// Non-empty → format-logo row (Concept F). Empty → compact row.
  final List<FormatTag> formatTags;

  /// The name and description halves of the imported stream badge rules'
  /// input (see [StreamBadgeStripFor]; `Torrent.name` and
  /// `Torrent.badgeDescription`). A null [badgeName] draws no rule badges.
  final String? badgeName;
  final String? badgeDescription;

  /// Neutral resolution pill for the compact row (e.g. "1080p"). Ignored when
  /// [formatTags] is non-empty (the logos carry resolution).
  final String? qualityTag;

  /// e.g. "TB | PM" — rendered as the green ⚡ cache pill. Null → no pill.
  final String? cacheLabel;

  /// e.g. "Season Pack" / "S01E01" — neutral coverage badge. Null → none.
  final String? coverageBadge;

  /// "Direct" / "External" for addon streams. Null → not a stream.
  final String? streamBadge;

  final bool isTelevision;

  /// Show the "Play" pill when focused (TV). The tap still runs the configured
  /// activate action; the pill is an affordance, not a promise of "play".
  final bool showPlayPill;

  /// Multi-select mode (keyword bulk actions): a leading check indicator
  /// replaces the play affordance and [isSelected] accents the card.
  final bool isSelectionMode;
  final bool isSelected;

  /// Copy-link affordance. It occupies the existing trailing-action slot
  /// instead of being added beside the chevron, so enabling it does not take
  /// width away from the card text. Touch-only — not DPAD-focusable.
  final VoidCallback? onCopy;

  /// Title line cap. Defaults to the layout's own rule (2 for the compact
  /// row, 1 for the format-logo row); keyword rows pass 2 — raw release
  /// names carry their meaning in the tail, so one line truncates too much.
  final int? titleMaxLines;

  final VoidCallback? onLongPress;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;

  @override
  State<SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends State<SourceRow> {
  static const _accent = Color(0xFF7B5CFF);
  static const _cache = Color(0xFF35C88A);
  static const _surface = Color(0xFF161320);
  static const _surfaceHi = Color(0xFF1E1B2C);
  static const _fg = Color(0xFFF1F1F6);
  static final _dim = const Color(0xFFF1F1F6).withValues(alpha: 0.52);
  static final _dim2 = const Color(0xFFF1F1F6).withValues(alpha: 0.30);
  static final _tagBg = const Color(0xFFFFFFFF).withValues(alpha: 0.06);
  static final _tagFg = const Color(0xFFF1F1F6).withValues(alpha: 0.74);

  bool _isFocused = false;
  Timer? _longPressTimer;
  bool _longPressTriggered = false;

  /// A source activates on key-up so a hold can run its secondary action.
  /// Require the matching down on this row; focus can arrive while the key
  /// that opened the Sources page is already held, leaving only its release.
  bool _sawSelectDown = false;
  static const _longPressDuration = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant SourceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A toolbar rebuild (sort/filter/source pill) replaces the FocusNode while
    // this State is reused by position — migrate the listener to the new node
    // or the focus border / Play pill / auto-scroll silently stop reacting.
    if (oldWidget.focusNode != widget.focusNode) {
      _cancelSelectPress();
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
      final focused = widget.focusNode.hasFocus;
      if (focused != _isFocused) _isFocused = focused;
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _cancelSelectPress();
    super.dispose();
  }

  void _cancelSelectPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _longPressTriggered = false;
    _sawSelectDown = false;
  }

  void _onFocusChange() {
    if (!mounted) return;
    final focused = widget.focusNode.hasFocus;
    if (!focused) _cancelSelectPress();
    if (_isFocused != focused) {
      setState(() => _isFocused = focused);
      if (focused) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.3,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (isActivateKey(event.logicalKey)) {
      if (event is KeyDownEvent) {
        _sawSelectDown = true;
        _longPressTriggered = false;
        _longPressTimer?.cancel();
        _longPressTimer = Timer(_longPressDuration, () {
          if (!mounted) return;
          _longPressTriggered = true;
          (widget.onLongPress ?? widget.onTap)();
        });
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        _longPressTimer?.cancel();
        _longPressTimer = null;
        final wasPress = _sawSelectDown && !_longPressTriggered;
        _sawSelectDown = false;
        _longPressTriggered = false;
        if (wasPress) widget.onTap();
        return KeyEventResult.handled;
      } else if (event is KeyRepeatEvent) {
        return KeyEventResult.handled;
      }
    }
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        widget.onNavigateUp?.call();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        widget.onNavigateDown?.call();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Legacy keeps the row's own cursor — the 1.5px accent border and the hard
    // 3px halo around it. `FocusTokens.legacy` is 2.5 wide and takes no
    // override, so the box would draw a heavier ring than this row has ever
    // worn; off legacy the theme's expression takes the job outright.
    //
    // The focused FILL stays on both paths: it is the row responding to the
    // cursor, not the cursor itself, so a theme that expresses focus as an
    // underline still lights the row it is under.
    final ownCursor = AppThemeScope.of(context).isLegacy;
    final content = Container(
      decoration: BoxDecoration(
        color: _isFocused ? _surfaceHi : _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          // The width never changes, focused or not — a border insets its
          // child, and a row that reflows on focus is the thing this widget
          // has always avoided.
          color: _isFocused && ownCursor
              ? _accent
              : widget.isSelected
                  ? _accent.withValues(alpha: 0.55)
                  : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: _isFocused && ownCursor
            ? [BoxShadow(color: _accent.withValues(alpha: 0.22), blurRadius: 0, spreadRadius: 3)]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.isSelectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 11),
                child: Icon(
                  widget.isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 21,
                  color: widget.isSelected ? _accent : _dim2,
                ),
              ),
            Expanded(child: _buildBody()),
            if (widget.showPlayPill && _isFocused && !widget.isSelectionMode) ...[
              const SizedBox(width: 8),
              _playPill(),
            ],
            if (widget.onCopy != null && !widget.isSelectionMode)
              SizedBox.square(
                dimension: 28,
                child: ExcludeFocus(
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    splashRadius: 18,
                    tooltip: 'Copy link',
                    onPressed: widget.onCopy,
                    icon: Icon(Icons.copy_rounded, color: _dim2),
                  ),
                ),
              )
            else ...[
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: _isFocused ? _accent : _dim2,
              ),
            ],
          ],
        ),
      ),
    );

    // On TV the Focus key-handler owns activation (no GestureDetector, to avoid
    // a double-fire); on touch a GestureDetector provides tap/long-press.
    final focusable = Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _handleKeyEvent,
      child: ownCursor
          ? content
          : FocusExpressionBox(
              focused: _isFocused,
              radius: 14,
              // Full-width row: the poster-scale parallax lift pushed 5% of
              // the row past both screen edges — the focused source read as
              // cut off on the left. settingsRow lifts just enough to
              // separate from its neighbours.
              shape: ParallaxShape.settingsRow,
              // The focused fill is what the ring lands on, and it is nearly
              // black — a theme with a dark cursor needs the rescue here.
              on: _surfaceHi,
              child: content,
            ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: widget.isTelevision
          ? focusable
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              child: focusable,
            ),
    );
  }

  Widget _buildBody() {
    final topBadges = <Widget>[
      if (widget.formatTags.isEmpty && widget.qualityTag != null)
        _pill(widget.qualityTag!, _tagFg, _tagBg, weight: FontWeight.w700),
      if (widget.coverageBadge != null)
        _pill(widget.coverageBadge!, _tagFg, _tagBg),
      if (widget.streamBadge != null)
        _pill(widget.streamBadge!, _tagFg, _tagBg),
      if (widget.cacheLabel != null)
        _pill('⚡ ${widget.cacheLabel}', _cache, _cache.withValues(alpha: 0.12)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (topBadges.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Wrap(spacing: 7, runSpacing: 5, children: topBadges),
          ),
        Text(
          widget.title,
          maxLines: widget.titleMaxLines ?? (widget.formatTags.isEmpty ? 2 : 1),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _fg,
            fontSize: widget.formatTags.isEmpty ? 13 : 15,
            fontWeight: widget.formatTags.isEmpty ? FontWeight.w500 : FontWeight.w700,
            height: 1.3,
          ),
        ),
        if (widget.subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              widget.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _dim, fontSize: 12, height: 1.3),
            ),
          ),
        if (widget.formatTags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FormatBadgeRow(
              widget.formatTags,
              scale: widget.isTelevision ? 1.12 : 1.0,
            ),
          ),
        if (widget.badgeName != null)
          StreamBadgeStripFor(
            name: widget.badgeName!,
            description: widget.badgeDescription,
            height: widget.isTelevision ? 22 : 20,
            builder: (strip) => Padding(
              padding: EdgeInsets.only(
                top: widget.formatTags.isNotEmpty ? 8 : 10,
              ),
              child: strip,
            ),
          ),
      ],
    );
  }

  Widget _pill(String text, Color fg, Color bg, {FontWeight weight = FontWeight.w700}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: weight, height: 1)),
  );

  Widget _playPill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
    decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(999)),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
        SizedBox(width: 5),
        Text('Play', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
