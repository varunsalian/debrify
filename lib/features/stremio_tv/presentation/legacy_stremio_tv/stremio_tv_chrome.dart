import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StremioTvChrome {
  StremioTvChrome(this._deps);
  final StremioTvDependencies _deps;
  StremioTvOwners get _owners => _deps.owners;

  /// Wraps a MenuItemButton inside a submenu with DPAD navigation:
  /// - Left/Right arrow: close submenu, return to parent SubmenuButton
  /// - Escape/Back: close entire menu, return to 3-dot button
  Widget submenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool autofocus = false,
  }) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          // Close just the submenu — focus parent SubmenuButton
          _owners.focus.submenuFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.goBack) {
          // Close entire menu
          _owners.focus.menuController.close();
          _owners.focus.menuFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MenuItemButton(
        autofocus: autofocus,
        leadingIcon: Icon(icon),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }

  Widget topMenuItem({
    required Widget leadingIcon,
    required String label,
    required VoidCallback onPressed,
    required MenuController controller,
    required FocusNode anchorFocusNode,
    bool autofocus = false,
    bool closeOnArrowUp = false,
  }) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if ((closeOnArrowUp &&
                event.logicalKey == LogicalKeyboardKey.arrowUp) ||
            event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.goBack) {
          controller.close();
          anchorFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MenuItemButton(
        autofocus: autofocus,
        leadingIcon: leadingIcon,
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }

  Widget headerButton({
    required bool focused,
    required Widget child,
    bool active = false,
    bool wide = false,
    VoidCallback? onTap,
  }) {
    final app = AppThemeScope.of(_deps.context());
    final btn = Container(
      height: 40,
      constraints: wide ? const BoxConstraints(minWidth: 48) : null,
      width: wide ? null : 40,
      padding: wide ? const EdgeInsets.symmetric(horizontal: 12) : null,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Home chrome language (matches the Catalog/Keyword mode toggle): an
        // active control fills with the purple accent; focus is a white ring
        // that shows even on the active one, since DPAD focus lands there first
        // and the fill alone wouldn't signal the remote moved.
        color: active ? app.home.chromeAccent : app.stremioTv.surfaceFill,
        borderRadius: app.shape.br(12),
        border: Border.all(
          color: focused ? app.stremioTv.focusRing : app.stremioTv.hairline,
          width: focused ? 2 : 0.5,
        ),
      ),
      child: child,
    );
    if (onTap != null) return GestureDetector(onTap: onTap, child: btn);
    return btn;
  }

  Widget buildLoadingSkeleton() {
    final app = AppThemeScope.of(_deps.context());
    return Column(
      children: [
        const SizedBox(height: 52),
        // Skeleton stage area
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: app.core.tx.withValues(alpha: 0.03),
              borderRadius: app.shape.br(20),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 48,
                  bottom: 60,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 80,
                        height: 28,
                        decoration: BoxDecoration(
                          color: app.core.tx.withValues(alpha: 0.06),
                          borderRadius: app.shape.br(10),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: 320,
                        height: 36,
                        decoration: BoxDecoration(
                          color: app.stremioTv.surfaceFill,
                          borderRadius: app.shape.br(8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 200,
                        height: 16,
                        decoration: BoxDecoration(
                          color: app.core.tx.withValues(alpha: 0.03),
                          borderRadius: app.shape.br(6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Skeleton dial cards
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 32),
            itemCount: 6,
            itemBuilder: (context, i) {
              return Container(
                width: 138,
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                decoration: BoxDecoration(
                  color: app.stremioTv.surfaceFill,
                  borderRadius: app.shape.br(16),
                  border: Border.all(
                    color: app.core.tx.withValues(alpha: 0.04),
                    width: 0.5,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
