import 'package:flutter/material.dart';

import '../../../models/debrify_tv/channel.dart';
import '../../../theme/app_theme_scope.dart';
import 'spotlight_rail.dart' show SpotlightKick;

/// The acting stage beside the rail: the focused channel's identity, its
/// keywords, and the action row. Purely presentational — focus routing lives
/// in the arm, data comes from the view.
///
/// The stage may NOT promise what plays (mock §3): Debrify TV has no running
/// order — `_selectTorrentsForPlayback` ends in a shuffle, provider cache-hit
/// is unknown until the provider answers, and size is a per-file rule. So
/// nothing on this surface is ever captioned as "up next".
class SpotlightStage extends StatelessWidget {
  final DebrifyTvChannel? channel;
  final bool pinned;
  final bool busy;

  final FocusNode playNode;
  final FocusNode pinNode;
  final FocusNode editNode;
  final FocusNode shareNode;
  final FocusNode deleteNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;

  final VoidCallback onWatch;
  final VoidCallback onTogglePin;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onAdd;
  final VoidCallback onImport;

  const SpotlightStage({
    super.key,
    required this.channel,
    required this.pinned,
    required this.busy,
    required this.playNode,
    required this.pinNode,
    required this.editNode,
    required this.shareNode,
    required this.deleteNode,
    required this.onKey,
    required this.onWatch,
    required this.onTogglePin,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
    required this.onAdd,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final ch = channel;
    if (ch == null) {
      // No channels at all. The redesigned empty surface is a phase-7
      // deliverable; until it lands this stays a quiet prompt (the rail's
      // Add / Import rows are the actionable path).
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Make a channel out of anything you can name.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: app.core.tx,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Add a channel or import a pack from the rail on the left.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: tv.textDim),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Identity ────────────────────────────────────────────────
        SpotlightKick(
          'Channel ${ch.channelNumber.toString().padLeft(2, '0')}'
          '${pinned ? ' · Pinned' : ''}',
          color: tv.accent,
        ),
        const SizedBox(height: 7),
        Text(
          ch.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 37,
            height: 0.98,
            letterSpacing: -1.2,
            fontWeight: FontWeight.w800,
            color: app.core.tx,
          ),
        ),
        const SizedBox(height: 13),
        // ── Keywords ────────────────────────────────────────────────
        _KeywordRow(keywords: ch.keywords),
        const Spacer(),
        // ── Actions ─────────────────────────────────────────────────
        Row(
          children: [
            _ActionButton(
              focusNode: playNode,
              onKey: onKey,
              onActivate: busy ? null : onWatch,
              icon: Icons.play_arrow_rounded,
              label: 'Tune in',
              primary: true,
            ),
            const SizedBox(width: 7),
            _ActionButton(
              focusNode: pinNode,
              onKey: onKey,
              onActivate: onTogglePin,
              icon: pinned ? Icons.star_rounded : Icons.star_outline_rounded,
              tooltip: pinned ? 'Unpin' : 'Pin to the top of the rail',
            ),
            const SizedBox(width: 7),
            _ActionButton(
              focusNode: editNode,
              onKey: onKey,
              onActivate: onEdit,
              icon: Icons.edit_rounded,
              tooltip: 'Edit channel',
            ),
            const SizedBox(width: 7),
            _ActionButton(
              focusNode: shareNode,
              onKey: onKey,
              onActivate: onShare,
              icon: Icons.share_rounded,
              tooltip: 'Share channel',
            ),
            const SizedBox(width: 7),
            _ActionButton(
              focusNode: deleteNode,
              onKey: onKey,
              onActivate: onDelete,
              icon: Icons.delete_outline_rounded,
              tooltip: 'Delete channel',
              danger: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _KeywordRow extends StatelessWidget {
  final List<String> keywords;
  const _KeywordRow({required this.keywords});

  static const int _shown = 5;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final visible = keywords.take(_shown).toList();
    final more = keywords.length - visible.length;
    return Wrap(
      spacing: 5.5,
      runSpacing: 5.5,
      children: [
        for (final kw in visible)
          Container(
            height: 25,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: tv.fillWeak,
              borderRadius: BorderRadius.circular(12.5),
              border: Border.all(color: tv.hairline, width: 1),
            ),
            alignment: Alignment.center,
            child: Text(
              kw,
              style: TextStyle(fontSize: 10.5, color: tv.textDim),
            ),
          ),
        if (more > 0)
          Container(
            height: 25,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: Text(
              '+$more more',
              style: TextStyle(fontSize: 10.5, color: tv.textFaint),
            ),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final VoidCallback? onActivate;
  final IconData icon;
  final String? label;
  final String? tooltip;
  final bool primary;
  final bool danger;

  const _ActionButton({
    required this.focusNode,
    required this.onKey,
    required this.onActivate,
    required this.icon,
    this.label,
    this.tooltip,
    this.primary = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: onKey,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          final disabled = onActivate == null;
          // Danger focus is the mock's literal pair — this surface already
          // paints its delete affordances a literal red (grid options menu).
          const dangerFill = Color(0xFFFFE3E5);
          const dangerInk = Color(0xFF8A1420);
          final Color fill = focused
              ? (danger ? dangerFill : app.core.tx)
              : primary
              ? app.core.tx.withValues(alpha: disabled ? 0.4 : 0.92)
              : tv.fillWeak;
          final Color ink = focused
              ? (danger ? dangerInk : app.inkOn(app.core.tx))
              : primary
              ? app.inkOn(app.core.tx)
              : tv.textDim;
          final child = RepaintBoundary(
            child: GestureDetector(
              onTap: onActivate,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                height: 44,
                width: label == null ? 44 : null,
                padding: label == null
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 21),
                transform: focused
                    ? (Matrix4.identity()..translateByDouble(0, -3, 0, 1))
                    : Matrix4.identity(),
                transformAlignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: focused ? fill : tv.hairline,
                    width: 1,
                  ),
                  boxShadow: focused
                      ? const [
                          BoxShadow(
                            color: Color(0x73000000),
                            blurRadius: 24,
                            offset: Offset(0, 12),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 15, color: ink),
                    if (label != null) ...[
                      const SizedBox(width: 7),
                      Text(
                        label!,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
          if (tooltip == null) return child;
          return Tooltip(message: tooltip!, child: child);
        },
      ),
    );
  }
}
