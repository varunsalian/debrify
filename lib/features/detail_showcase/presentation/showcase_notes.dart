import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:flutter/material.dart';

/// A band that has nothing to show yet, or could not load.
///
/// Without this a failed episode load reads as the band simply not being
/// there — indistinguishable from a movie, and with no way to retry.
class ShowcaseBandNote extends StatelessWidget {
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Supplied by the layout so the chip joins the band ladder. A focusable
  /// control the DPAD map does not know about is a control nobody can reach.
  final FocusNode? actionNode;

  const ShowcaseBandNote({
    super.key,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.actionNode,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(m.gutter, 22, m.gutter, 8),
      child: Row(
        children: [
          Text(text, style: st(11.5 * m.k, a: 0.66)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 12),
            _RetryChip(label: actionLabel!, onTap: onAction!, node: actionNode),
          ],
        ],
      ),
    );
  }
}

class _RetryChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final FocusNode? node;

  const _RetryChip({required this.label, required this.onTap, this.node});

  @override
  State<_RetryChip> createState() => _RetryChipState();
}

class _RetryChipState extends State<_RetryChip> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) => setState(() => _f = v),
      onKeyEvent: (_, e) => sActivate(e, widget.onTap),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 22 * k,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 11 * k),
          decoration: BoxDecoration(
            color: _f ? sInk : sInk.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(11 * k),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 10.5 * k,
              fontWeight: FontWeight.w600,
              color: _f ? Colors.black : sInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// The Details band — Creator/Country/Language/Studio/Box Office, and awards.
///
/// Reference material, not a row of verbs, so it sits at the very bottom and
/// takes no cursor. Two columns because a single column of five short pairs
/// leaves a screen mostly empty at three metres.
class ShowcaseDetails extends StatelessWidget {
  final List<(String, String)> rows;
  final String? awards;

  const ShowcaseDetails({super.key, required this.rows, required this.awards});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && (awards ?? '').isEmpty) return const SizedBox.shrink();
    final m = ShowcaseMetrics.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(m.gutter, 26, m.gutter, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Details', style: st(13 * m.k, w: FontWeight.w600, a: 0.84)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 46,
            runSpacing: 7,
            children: [
              for (final r in rows)
                SizedBox(
                  width: 240 * m.k,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 74 * m.k,
                        child: Text(r.$1, style: st(10 * m.k, a: 0.5)),
                      ),
                      Expanded(child: Text(r.$2, style: st(10 * m.k, a: 0.82))),
                    ],
                  ),
                ),
            ],
          ),
          if ((awards ?? '').isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(awards!, style: st(10 * m.k, a: 0.6)),
          ],
        ],
      ),
    );
  }
}
