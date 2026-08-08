import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme_scope.dart';
import '../../utils/tv_keys.dart';

/// Shared top bar for the See-All screens: a back button + title/subtitle.
///
/// On TV the back button is a DPAD focus stop — SELECT pops the route and
/// DPAD-down enters the filter bar (via [onFilterDown]). Off-TV it's a plain
/// tappable button.
class SeeAllHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isTelevision;
  final FocusNode backNode;

  /// DPAD-down from the back button — hand focus to the first filter control.
  final VoidCallback onFilterDown;

  const SeeAllHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.backNode,
    required this.onFilterDown,
    this.isTelevision = false,
  });

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!isTelevision || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      onFilterDown();
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    if (isActivateKey(key) ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      // Keys only arrive while the node is focused, so its context is attached.
      final ctx = node.context;
      if (ctx != null) Navigator.of(ctx).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 24, 6),
      child: Row(
        children: [
          Focus(
            focusNode: backNode,
            onKeyEvent: _onKey,
            child: Builder(builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: app.seeAll.panel,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: focused ? app.seeAll.accent : app.seeAll.line,
                      width: focused ? 2 : 1,
                    ),
                  ),
                  child: Icon(Icons.arrow_back_rounded,
                      size: 20, color: app.core.tx),
                ),
              );
            }),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: app.fade(app.core.tx, 0.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
