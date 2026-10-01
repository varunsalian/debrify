import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme_scope.dart';
import '../../../utils/tv_keys.dart';

/// A pill knob switch, purple when on. Purely visual — the parent row owns the
/// tap/DPAD toggle so the whole row is one focus target.
class _SrcMiniToggle extends StatelessWidget {
  final bool value;
  const _SrcMiniToggle({required this.value});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      width: 44,
      height: 26,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: value ? app.home.chromeAccent : app.fade(app.core.tx, 0.16),
        borderRadius: app.shape.brPill,
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            // ON, the knob sits on the OPAQUE accent track — a hardcoded white
            // knob is invisible on Noir's/Frost's #FFFFFF accent, so it is
            // scored like ink. OFF, the track is a dim wash over the dialog,
            // where page ink is what reads.
            color: value ? app.inkOn(app.home.chromeAccent) : app.core.tx,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// One toggle row in a Sources dialog: leading state chip, label (+ optional
/// subtitle), trailing [_SrcMiniToggle]. Focusable — Select/OK or tap flips it,
/// arrows fall through to directional focus so the list is DPAD-navigable.
class SourceToggleRow extends StatefulWidget {
  final String label;
  final String? subtitle;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<bool> onToggle;
  const SourceToggleRow({
    super.key,
    required this.label,
    required this.enabled,
    required this.onToggle,
    this.subtitle,
    this.autofocus = false,
  });

  @override
  State<SourceToggleRow> createState() => _SourceToggleRowState();
}

class _SourceToggleRowState extends State<SourceToggleRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final on = widget.enabled;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          widget.onToggle(!on);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onToggle(!on),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _focused
                ? app.fade(app.core.tx, 0.08)
                : app.fade(app.core.tx, 0.03),
            borderRadius: app.shape.br(14),
            border: Border.all(
              color: _focused
                  ? app.fade(app.core.tx, 0.9)
                  : app.fade(app.core.tx, 0.06),
              width: _focused ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on
                      ? app.fade(app.home.chromeAccent, 0.18)
                      : app.fade(app.core.tx, 0.05),
                  borderRadius: app.shape.br(10),
                ),
                child: Icon(
                  on ? Icons.check_circle_rounded : Icons.block_rounded,
                  size: 18,
                  color: on
                      ? app.home.chromeAccent
                      : app.fade(app.core.tx, 0.3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: app.fade(app.core.tx, on ? 0.95 : 0.55),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        widget.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: app.fade(app.core.tx, 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _SrcMiniToggle(value: on),
            ],
          ),
        ),
      ),
    );
  }
}
