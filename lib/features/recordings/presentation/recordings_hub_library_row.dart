import 'package:debrify/features/recordings/presentation/recordings_hub_buttons.dart';
import 'package:debrify/features/recordings/presentation/recordings_hub_tokens.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/iptv/iptv_stage_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Library row ─────────────────────────────────────────────────────────────
class _LibraryRow extends StatefulWidget {
  final FocusNode? focusNode;
  final String title;
  final String subtitle;
  final String monogramName;
  final bool autofocus;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  const _LibraryRow({
    this.focusNode,
    required this.title,
    required this.subtitle,
    required this.monogramName,
    required this.autofocus,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  State<_LibraryRow> createState() => _LibraryRowState();
}

typedef RecordingsHubLibraryRow = _LibraryRow;

class _LibraryRowState extends State<_LibraryRow> {
  /// Live, never cached: Flutter does not guarantee the falling edge of
  /// `onFocusChange` — popping a route opened with OK restores focus to the
  /// modal scope rather than to a row, so rows that were focus-walked on the
  /// way in are never told they lost it and keep painting as focused. See the
  /// note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode());
  bool get _focused => _focusNode.hasFocus;

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _focused
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused
              ? kRecordingsHubGold
              : Colors.white.withValues(alpha: 0.06),
          width: _focused ? 1.8 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              onFocusChange: (_) => setState(() {}),
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    isActivateOrSpaceKey(event.logicalKey)) {
                  widget.onPlay();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                onTap: widget.onPlay,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
                  child: Row(
                    children: [
                      _Thumb(
                        monogramName: widget.monogramName,
                        highlight: _focused,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11.5,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          RecordingsHubRowIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete recording',
            onPressed: widget.onDelete,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String monogramName;
  final bool highlight;
  const _Thumb({required this.monogramName, required this.highlight});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1F3D), Color(0xFF0C0F22)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IptvMonogram(name: monogramName, size: 26),
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: highlight
                    ? kRecordingsHubGold
                    : Colors.black.withValues(alpha: 0.55),
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                size: 14,
                color: highlight ? Colors.black : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
