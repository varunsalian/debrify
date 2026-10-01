import 'package:flutter/material.dart';

import '../../../models/torrent.dart';
import '../../../theme/app_theme_scope.dart';
import '../application/keyword_provider_selection.dart';
import 'keyword_source_label.dart';

/// Keeps every source tab mounted so remote focus can reach off-screen tabs.
class KeywordSourceTabs extends StatelessWidget {
  const KeywordSourceTabs({
    super.key,
    required this.sources,
    required this.full,
    required this.selectedSource,
    required this.focusNodes,
    required this.onKey,
    required this.onChanged,
  });
  final List<String> sources;
  final List<Torrent> full;
  final String? selectedSource;
  final List<FocusNode> focusNodes;
  final KeyEventResult Function(int, int, VoidCallback, KeyEvent) onKey;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final accent = app.home.chromeAccent;
    final dim = app.fade(app.core.tx, 0.55);
    final counts = <String, int>{};
    for (final t in full) {
      counts[keywordSourceOf(t)] = (counts[keywordSourceOf(t)] ?? 0) + 1;
    }
    final total = sources.length + 1;

    Widget tab(int navIndex, String label, bool on, VoidCallback onTap) {
      // Nodes are synced in _recomputeKeyword; a mid-build mismatch (e.g. the
      // strip rebuilt by a non-recompute setState) must not range-crash.
      final node = navIndex < focusNodes.length ? focusNodes[navIndex] : null;
      Widget body(bool focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: on ? accent : app.fade(app.core.tx, 0.05),
          borderRadius: app.shape.brPill,
          // Always 2px so focus never shifts layout.
          border: Border.all(
            color: focused ? app.fade(app.core.tx, 0.9) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            // Scored against the fill the selected tab actually paints.
            // `accent` IS the theme accent, and white fails on 17 of the 18
            // selectable themes (Noir's and Frost's are #FFFFFF), so a
            // hardcoded white label vanished into its own pill. Legacy's
            // #7B5CFF scores 4.36 against white, so inkOn still returns white
            // there — no visual change to today's app.
            color: on ? app.inkOn(accent) : dim,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      final Widget tappable = node == null
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: app.shape.brPill,
                child: body(false),
              ),
            )
          : Focus(
              focusNode: node,
              onKeyEvent: (n, e) => onKey(navIndex, total, onTap, e),
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: app.shape.brPill,
                      canRequestFocus: false,
                      child: body(focused),
                    ),
                  );
                },
              ),
            );
      return Padding(padding: const EdgeInsets.only(right: 6), child: tappable);
    }

    // SingleChildScrollView + Row (not a lazy ListView) so EVERY tab's
    // FocusNode stays mounted — requestFocus on an unmounted node is a silent
    // no-op that would strand DPAD at the viewport edge (same reason the
    // keyword toolbar uses this shape).
    return SizedBox(
      height: 42,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          children: [
            tab(
              0,
              'All · ${full.length}',
              selectedSource == null,
              () => onChanged(null),
            ),
            for (var i = 0; i < sources.length; i++)
              tab(
                i + 1,
                '${keywordSourceLabel(full, sources[i])} · ${counts[sources[i]] ?? 0}',
                selectedSource == sources[i],
                () => onChanged(sources[i]),
              ),
          ],
        ),
      ),
    );
  }
}
