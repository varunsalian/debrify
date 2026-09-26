import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';
import 'package:flutter/services.dart';
import '../../../utils/tv_keys.dart';

/// A focusable pill button for the Sources dialog header/footer actions
/// (Enable all / Disable all / Done). Filled = purple primary (Done).
class SourceActionChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const SourceActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  State<SourceActionChip> createState() => _SourceActionChipState();
}

class _SourceActionChipState extends State<SourceActionChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: widget.filled
                ? app.fade(app.home.chromeAccent, _focused ? 1.0 : 0.9)
                : app.fade(app.core.tx, _focused ? 0.14 : 0.06),
            borderRadius: app.shape.brPill,
            border: Border.all(
              color: _focused
                  ? app.fade(app.core.tx, 0.9)
                  : app.fade(app.core.tx, 0.12),
              width: _focused ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                // Filled = the accent at 0.9–1.0 alpha over an opaque dialog,
                // i.e. effectively the accent itself; score the ink against it
                // (alpha is ignored by inkOn) instead of assuming white.
                color: widget.filled
                    ? app.inkOn(app.home.chromeAccent)
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.filled
                      ? app.inkOn(app.home.chromeAccent)
                      : scheme.onSurface,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
