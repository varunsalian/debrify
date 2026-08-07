import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/debrify_image_cache.dart';
import '../../utils/platform_util.dart';
import '../tracker_brand_marks.dart';
import 'detail_model.dart';
import 'detail_style.dart';

/// Shared identity + action vocabulary for the alternate detail layouts.
///
/// Deliberately a parallel set to Classic's private widgets rather than a
/// refactor of them: Classic must stay byte-identical, and its versions carry
/// assumptions from its own two-pane focus model.

// ── Buttons ────────────────────────────────────────────────────────────────

class DetailPrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final Color glow;

  const DetailPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.glow,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<DetailPrimaryButton> createState() => _DetailPrimaryButtonState();
}

class _DetailPrimaryButtonState extends State<DetailPrimaryButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return DetailFocusRing(
      focused: _focused,
      radius: BorderRadius.circular(999),
      // A static drop shadow, rasterised once and carried by the transform —
      // not a per-frame backdrop blur, which the weak TV GPU cannot afford.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: widget.glow.withValues(alpha: 0.42),
              blurRadius: 18,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Material(
          color: const Color(0xFFF6F5F0),
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onFocusChange: (f) => setState(() => _focused = f),
            borderRadius: BorderRadius.circular(999),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.play_arrow_rounded,
                    color: Color(0xFF0D0D10),
                    size: 19,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Color(0xFF0D0D10),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
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

class DetailGhostButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;
  final FocusNode? focusNode;

  const DetailGhostButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
    this.focusNode,
  });

  @override
  State<DetailGhostButton> createState() => _DetailGhostButtonState();
}

class _DetailGhostButtonState extends State<DetailGhostButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return DetailFocusRing(
      focused: _focused,
      radius: BorderRadius.circular(999),
      child: Material(
        color: DetailPalette.glass,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          focusNode: widget.focusNode,
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: DetailPalette.hair),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                else
                  Icon(widget.icon, color: Colors.white, size: 16),
                const SizedBox(width: 7),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

class DetailSourcePill extends StatefulWidget {
  final int count;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;

  const DetailSourcePill({
    super.key,
    required this.count,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<DetailSourcePill> createState() => _DetailSourcePillState();
}

class _DetailSourcePillState extends State<DetailSourcePill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bound = widget.count > 0;
    const gold = DetailPalette.gold;
    final label = bound
        ? (widget.count > 1 ? '${widget.count} sources' : '1 source')
        : 'Bind source';
    return DetailFocusRing(
      focused: _focused,
      radius: BorderRadius.circular(999),
      child: Material(
        color: bound
            ? gold.withValues(alpha: 0.13)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: bound
                    ? gold.withValues(alpha: 0.30)
                    : DetailPalette.hair,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  bound ? Icons.link_rounded : Icons.link_off_rounded,
                  color: bound ? gold : Colors.white70,
                  size: 15,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: bound ? gold : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class DetailRoundButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;
  final FocusNode? focusNode;

  const DetailRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 40,
    this.focusNode,
  });

  @override
  State<DetailRoundButton> createState() => _DetailRoundButtonState();
}

class _DetailRoundButtonState extends State<DetailRoundButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return DetailFocusRing(
      focused: _focused,
      child: Material(
        color: DetailPalette.glass,
        shape: CircleBorder(side: BorderSide(color: DetailPalette.hair)),
        child: InkWell(
          customBorder: const CircleBorder(),
          focusNode: widget.focusNode,
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Icon(widget.icon, color: Colors.white, size: 19),
          ),
        ),
      ),
    );
  }
}

/// A tracker's identity, live state and rating in one control.
class DetailTrackerPill extends StatefulWidget {
  final Widget mark;
  final String brand;
  final String state;
  final int? rating;
  final Color accent;
  final bool tracked;

  /// Drops the brand eyebrow — for narrow columns where it costs more than it
  /// tells.
  final bool compact;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const DetailTrackerPill({
    super.key,
    required this.mark,
    required this.brand,
    required this.state,
    required this.rating,
    required this.accent,
    required this.tracked,
    required this.onTap,
    this.compact = false,
    this.focusNode,
  });

  @override
  State<DetailTrackerPill> createState() => _DetailTrackerPillState();
}

class _DetailTrackerPillState extends State<DetailTrackerPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final tracked = widget.tracked;
    final radius = BorderRadius.circular(999);
    return DetailFocusRing(
      focused: _focused,
      radius: radius,
      child: Material(
        color: tracked
            ? accent.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: radius,
        child: InkWell(
          focusNode: widget.focusNode,
          borderRadius: radius,
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            padding: widget.compact
                ? const EdgeInsets.fromLTRB(6, 7, 12, 7)
                : const EdgeInsets.fromLTRB(10, 7, 14, 7),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: tracked
                    ? accent.withValues(alpha: 0.42)
                    : DetailPalette.hair,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.mark,
                SizedBox(width: widget.compact ? 7 : 9),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.compact) ...[
                      Text(
                        widget.brand,
                        style: TextStyle(
                          color: tracked
                              ? accent
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      widget.state,
                      style: TextStyle(
                        color: tracked
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.62),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                if (widget.rating != null) ...[
                  const SizedBox(width: 9),
                  Container(
                    height: 18,
                    width: 1,
                    color: accent.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.rating}',
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Composed pieces ────────────────────────────────────────────────────────

/// Runtime · year · certificate · IMDb rating.
class DetailMetaBar extends StatelessWidget {
  final DetailModel model;
  final double fontSize;

  const DetailMetaBar({super.key, required this.model, this.fontSize = 13});

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    void add(Widget w) {
      if (parts.isNotEmpty) parts.add(const SizedBox(width: 14));
      parts.add(w);
    }

    Widget text(String s) => Text(
      s,
      style: TextStyle(
        color: DetailPalette.tx2,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
      ),
    );

    final rt = model.runtime;
    if (rt != null) add(text(rt));
    final y = model.year;
    if (y != null && y.isNotEmpty) add(text(y));
    final cert = model.certificate;
    if (cert != null) {
      add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: DetailPalette.glass,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: DetailPalette.hair),
          ),
          child: Text(
            cert,
            style: TextStyle(
              fontSize: fontSize - 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    final r = model.rating;
    if (r != null) {
      add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              r.toStringAsFixed(1),
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: DetailPalette.imdb,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'IMDb',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 6,
      children: parts,
    );
  }
}

/// Logo (or a text wordmark when there is no logo art).
///
/// A drop shadow floor, not a look: metahub logo art is frequently
/// white-on-transparent and occasionally a black wordmark, so it has to stay
/// readable over artwork of any brightness.
class DetailLogo extends StatelessWidget {
  final DetailModel model;
  final double height;
  final double maxWidthFactor;

  const DetailLogo({
    super.key,
    required this.model,
    required this.height,
    this.maxWidthFactor = 0.62,
  });

  @override
  Widget build(BuildContext context) {
    final logo = model.logo;
    if (logo == null || logo.isEmpty) {
      return Text(
        model.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: height * 0.44,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.03 * height * 0.44,
          height: 1.03,
          shadows: const [Shadow(color: Colors.black87, blurRadius: 16)],
        ),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: height,
        maxWidth: MediaQuery.of(context).size.width * maxWidthFactor,
      ),
      child: CachedNetworkImage(
        imageUrl: logo,
        height: height,
        fit: BoxFit.contain,
        alignment: Alignment.bottomLeft,
        cacheManager: DebrifyImageCache.manager,
        // Logo art is often a huge transparent PNG; never decode it at full
        // resolution for a 70px lockup on a 2 GB box.
        memCacheHeight: (height * 3).round(),
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => Text(
          model.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: height * 0.44,
            fontWeight: FontWeight.w800,
            height: 1.03,
          ),
        ),
      ),
    );
  }
}

/// The action row, with the DPAD contract every layout needs.
///
/// Owns its own horizontal axis: LEFT/RIGHT walk the buttons in reading order
/// (the Wrap can break onto a second line, so ordering buckets by line first).
/// Without this, a geometric search picks whatever card sits below-right of the
/// row — which is how RIGHT used to fling the cursor into "More Like This".
class DetailActionRow extends StatelessWidget {
  final DetailModel model;

  /// Where RIGHT past the last button goes. Null dead-stops.
  final VoidCallback? onRightEdge;

  /// Where UP goes — every layout wires this to the back button.
  final VoidCallback? onUpEdge;

  /// Where DOWN goes; null lets directional traversal handle it.
  final VoidCallback? onDownEdge;

  final MainAxisAlignment alignment;

  /// Drops the tracker pills' brand eyebrow. For rows in a narrow column, where
  /// the extra width costs more than the word "TRAKT" tells.
  final bool compactTrackers;

  const DetailActionRow({
    super.key,
    required this.model,
    this.onRightEdge,
    this.onUpEdge,
    this.onDownEdge,
    this.alignment = MainAxisAlignment.start,
    this.compactTrackers = false,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (model.showPrimary)
        DetailPrimaryButton(
          label: model.primaryLabel,
          onTap: model.onPrimary,
          glow: model.accent,
          focusNode: model.focus.primaryEntry,
          autofocus: model.isTelevision,
        ),
      if (model.hasTrailer)
        DetailGhostButton(
          label: model.trailerPlaying ? 'Watch Trailer' : 'Trailer',
          icon: model.trailerPlaying
              ? Icons.play_circle_outline_rounded
              : Icons.movie_outlined,
          busy: model.trailerBusy,
          onTap: model.onTrailer,
        ),
      if (model.isMovie && model.onBrowse != null)
        DetailGhostButton(
          label: 'Sources',
          icon: Icons.layers_rounded,
          onTap: model.onBrowse!,
        ),
      if (model.onSelectSource != null)
        DetailSourcePill(
          count: model.sourceCount,
          onTap: model.onSelectSource!,
          // Takes the entry node only when Play is hidden (PikPak-only), so the
          // coordinator always has a live target — and with it the autofocus,
          // so the remote is never stranded on a page with no Play button.
          focusNode: model.showPrimary ? null : model.focus.primaryEntry,
          autofocus: model.isTelevision && !model.showPrimary,
        ),
      if (model.onAppMenu != null)
        DetailRoundButton(
          icon: Icons.more_horiz_rounded,
          tooltip: 'More',
          onTap: model.onAppMenu!,
        ),
      if (model.hasTrakt && model.onTraktMenu != null)
        DetailTrackerPill(
          mark: TraktMark(size: 19, opacity: model.traktTracked ? 1 : 0.55),
          brand: 'TRAKT',
          state: model.traktLabel,
          rating: model.traktRating,
          accent: kTraktRed,
          tracked: model.traktTracked,
          compact: compactTrackers,
          onTap: model.onTraktMenu!,
        ),
      if (model.hasSimkl && model.onSimklMenu != null)
        DetailTrackerPill(
          mark: SimklMark(size: 19, opacity: model.simklTracked ? 1 : 0.55),
          brand: 'SIMKL',
          state: model.simklLabel,
          rating: model.simklRating,
          accent: kSimklCyan,
          tracked: model.simklTracked,
          compact: compactTrackers,
          onTap: model.onSimklMenu!,
        ),
    ];

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) => _onKey(node, event),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: alignment == MainAxisAlignment.center
            ? WrapAlignment.center
            : WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: buttons,
      ),
    );
  }

  /// The row's DPAD model is 2-D, because the Wrap can break onto more than one
  /// line and those lines are visual rows.
  ///
  /// LEFT/RIGHT move within a line; UP/DOWN move between lines and only leave
  /// the row from the first/last one. RIGHT at the **right end of any line**
  /// crosses to whatever is to the right of the row — not just at the end of
  /// the whole sequence, which is what made a right pane unreachable from every
  /// line but the last.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    const handled = KeyEventResult.handled;
    if (key != LogicalKeyboardKey.arrowRight &&
        key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;

    // Bucket y into coarse lines: a centre-aligned Wrap leaves same-line
    // buttons of different heights a sub-pixel apart, which an exact compare
    // would read as separate lines. Wrap lines here are ≥36px apart.
    int lineOf(FocusNode n) => (n.rect.center.dy / 24).round();
    final all = node.traversalDescendants.toList()
      ..sort((a, b) {
        final dy = lineOf(a).compareTo(lineOf(b));
        return dy != 0 ? dy : a.rect.center.dx.compareTo(b.rect.center.dx);
      });
    if (!all.contains(primary)) return KeyEventResult.ignored;

    // Group into visual lines, preserving reading order.
    final lines = <List<FocusNode>>[];
    int? currentLine;
    for (final n in all) {
      final l = lineOf(n);
      if (lines.isEmpty || l != currentLine) {
        lines.add(<FocusNode>[]);
        currentLine = l;
      }
      lines.last.add(n);
    }
    final li = lines.indexWhere((l) => l.contains(primary));
    if (li < 0) return KeyEventResult.ignored;
    final line = lines[li];
    final xi = line.indexOf(primary);

    if (key == LogicalKeyboardKey.arrowRight) {
      if (xi < line.length - 1) {
        line[xi + 1].requestFocus();
      } else {
        onRightEdge?.call();
      }
      return handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      // Dead stop at a line's start: UP is the way out, and a geometric
      // fallback would dive into whatever sits below-left.
      if (xi > 0) line[xi - 1].requestFocus();
      return handled;
    }

    // Vertical: step between lines, keeping the nearest x, and only leave the
    // row from its first/last line.
    final down = key == LogicalKeyboardKey.arrowDown;
    final ni = down ? li + 1 : li - 1;
    if (ni < 0) {
      onUpEdge?.call();
      return onUpEdge == null ? KeyEventResult.ignored : handled;
    }
    if (ni >= lines.length) {
      onDownEdge?.call();
      return onDownEdge == null ? KeyEventResult.ignored : handled;
    }
    final x = primary.rect.center.dx;
    FocusNode nearest = lines[ni].first;
    var best = double.infinity;
    for (final n in lines[ni]) {
      final d = (n.rect.center.dx - x).abs();
      if (d < best) {
        best = d;
        nearest = n;
      }
    }
    nearest.requestFocus();
    return handled;
  }
}

/// Season chooser — the OK action on [DetailSeasonControl].
///
/// LEFT/RIGHT step; OK opens this, so the last season is not a dead end and a
/// long show doesn't need N presses to cross.
Future<void> showDetailSeasonPicker({
  required BuildContext context,
  required List<int> seasonNumbers,
  required int selected,
  required bool isTelevision,
  required void Function(int seasonNumber) onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF141019),
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetCtx).size.height * 0.7,
        ),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: seasonNumbers.length,
          itemBuilder: (context, i) {
            final n = seasonNumbers[i];
            final active = n == selected;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                autofocus: isTelevision && active,
                focusColor: Colors.white.withValues(alpha: 0.12),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  if (!active) onSelected(n);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 13, 18, 13),
                  child: Row(
                    children: [
                      Icon(
                        active
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 19,
                        color: active ? DetailPalette.focus : Colors.white38,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Season $n',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : DetailPalette.tx2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// Focusable `‹ Season N ▾ ›` control. Every series layout mounts one when the
/// show has more than one season, so the season is always reachable.
class DetailSeasonControl extends StatefulWidget {
  final int seasonNumber;
  final int episodeCount;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;
  final FocusNode? focusNode;
  final VoidCallback? onUpEdge;
  final VoidCallback? onDownEdge;

  /// TV hint for how to reach the per-episode menu in this layout.
  final String? hint;

  const DetailSeasonControl({
    super.key,
    required this.seasonNumber,
    required this.episodeCount,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    this.focusNode,
    this.onUpEdge,
    this.onDownEdge,
    this.hint,
  });

  @override
  State<DetailSeasonControl> createState() => _DetailSeasonControlState();
}

class _DetailSeasonControlState extends State<DetailSeasonControl> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.arrowUp && widget.onUpEdge != null) {
          widget.onUpEdge!();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown && widget.onDownEdge != null) {
          widget.onDownEdge!();
          return KeyEventResult.handled;
        }
        // One focusable, so LEFT/RIGHT step the season in place rather than
        // escaping the control.
        if (k == LogicalKeyboardKey.arrowLeft) {
          if (widget.canPrev) widget.onPrev();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowRight) {
          if (widget.canNext) widget.onNext();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DetailFocusRing(
            focused: _focused,
            radius: BorderRadius.circular(999),
            child: Material(
              color: DetailPalette.glass,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                focusNode: widget.focusNode,
                borderRadius: BorderRadius.circular(999),
                onTap: widget.onPick,
                onFocusChange: (f) => setState(() => _focused = f),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: DetailPalette.hair),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chevron_left_rounded,
                        size: 17,
                        color: widget.canPrev ? Colors.white70 : Colors.white24,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Season ${widget.seasonNumber}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 17,
                        color: widget.canNext ? Colors.white70 : Colors.white24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${widget.episodeCount} episodes',
            style: TextStyle(
              color: DetailPalette.tx3,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (widget.hint != null && PlatformUtil.isAndroidTvCached) ...[
            const SizedBox(width: 14),
            Text(
              widget.hint!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.30),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
