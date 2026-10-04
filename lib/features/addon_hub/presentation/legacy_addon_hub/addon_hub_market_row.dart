import 'package:debrify/features/addon_hub/presentation/addon_hub_addon_info.dart';
import 'package:debrify/features/addon_hub/presentation/addon_hub_focus_card.dart';
import 'package:debrify/features/addon_hub/presentation/addon_hub_row_nav.dart';
import 'package:debrify/services/stremio_marketplace_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/see_all/see_all_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AddonHubMarketRow extends StatelessWidget {
  final MarketplaceAddon addon;
  final bool installed;
  final VoidCallback onInstall;
  final VoidCallback onConfigure;

  /// Row-to-row DPAD navigation. [navIndex] is this row's slot in [nav] (null
  /// for installed rows, which aren't focusable); [navCount] is the total.
  final AddonHubRowNav nav;
  final int? navIndex;
  final int navCount;
  final bool warnDebrid;

  const AddonHubMarketRow({
    required this.addon,
    required this.installed,
    required this.onInstall,
    required this.onConfigure,
    required this.nav,
    required this.navIndex,
    required this.navCount,
    this.warnDebrid = false,
  });

  /// DOWN → next row's first button (always handled, so it never escapes the
  /// list sideways). UP → previous row's first button, or fall through to the
  /// filter bar when already at the top.
  bool _onDown() {
    nav.focus((navIndex ?? 0) + 1);
    return true;
  }

  bool _onUp() {
    final i = navIndex ?? 0;
    if (i == 0) return false; // let default traversal reach the filter bar
    nav.focus(i - 1);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Same responsive split as the installed card: below the breakpoint,
        // logo + title share a header row, the info flows full-width, and the
        // Install/Configure buttons drop to their own row (where they get room
        // instead of squeezing the info column).
        final narrow = c.maxWidth < 480;
        final meta = AddonHubAddonMeta(
          types: addon.types,
          resources: addon.resources,
          description: addon.description,
          warnDebrid: warnDebrid,
        );
        return Container(
          decoration: addonHubCardDecoration(false),
          padding: EdgeInsets.symmetric(
            horizontal: narrow ? 16 : 22,
            vertical: narrow ? 16 : 20,
          ),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        addonHubLogo(addon.logo, size: 44),
                        const SizedBox(width: 14),
                        Expanded(
                          child: AddonHubAddonTitleLine(
                            name: addon.name,
                            version: addon.version,
                            stacked: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    meta,
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _buildActions(),
                    ),
                  ],
                )
              : Row(
                  children: [
                    addonHubLogo(addon.logo),
                    const SizedBox(width: 20),
                    Expanded(
                      child: AddonHubAddonInfo(
                        name: addon.name,
                        version: addon.version,
                        types: addon.types,
                        resources: addon.resources,
                        description: addon.description,
                        warnDebrid: warnDebrid,
                      ),
                    ),
                    const SizedBox(width: 16),
                    _buildActions(),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildActions() {
    if (installed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: kSeeAllAccent2.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 6),
          Text(
            'Installed',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    // configurationRequired: config is mandatory, so there's no plain Install.
    // configurable (optional): offer both Install and Configure.
    // The row's FIRST button carries this row's nav node so DOWN/UP land on it.
    final primaryNode = navIndex != null ? nav.nodeAt(navIndex!) : null;
    final buttons = <Widget>[];
    if (!addon.configurationRequired) {
      buttons.add(
        AddonHubMarketButton(
          label: 'Install',
          primary: true,
          focusNode: primaryNode,
          onArrowDown: _onDown,
          onArrowUp: _onUp,
          onTap: onInstall,
        ),
      );
    }
    if (addon.configurationRequired || addon.configurable) {
      buttons.add(
        AddonHubMarketButton(
          label: 'Configure',
          focusNode: buttons.isEmpty ? primaryNode : null,
          onArrowDown: _onDown,
          onArrowUp: _onUp,
          onTap: onConfigure,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          buttons[i],
        ],
      ],
    );
  }
}

/// A stadium Install/Configure button matching the Stremio addons screen:
/// primary = solid accent fill, secondary = quiet outline. Constant 2px border
/// so focus never changes the button's size (no reflow shake).
class AddonHubMarketButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final FocusNode? focusNode;

  /// Return true if the arrow was consumed (focus moved / deliberately held).
  final bool Function()? onArrowUp;
  final bool Function()? onArrowDown;

  const AddonHubMarketButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.focusNode,
    this.onArrowUp,
    this.onArrowDown,
  });

  @override
  State<AddonHubMarketButton> createState() => _MarketButtonState();
}

class _MarketButtonState extends State<AddonHubMarketButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final Color fill;
    final Color borderColor;
    // The label/ring sit ON the accent fill when primary; the quiet variant sits
    // on the (untokenised) card, so its whites stay literal.
    final Color ink;
    if (widget.primary) {
      fill = _focused ? app.seeAll.accent2 : app.seeAll.accent;
      ink = app.inkOn(app.seeAll.accent);
      borderColor = _focused ? ink : Colors.transparent;
    } else {
      fill = _focused
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.transparent;
      borderColor = _focused
          ? Colors.white
          : Colors.white.withValues(alpha: 0.22);
      ink = Colors.white;
    }
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) addonHubCenterInScrollable(context);
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (isActivateKey(event.logicalKey)) {
          if (event is KeyDownEvent) widget.onTap();
          return KeyEventResult.handled;
        }
        // Vertical DPAD hops rows (Install↔Install, or Install→Configure-only) —
        // horizontal is left to default traversal (Install ↔ Configure in-row).
        if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
            widget.onArrowDown != null) {
          return widget.onArrowDown!()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
            widget.onArrowUp != null) {
          return widget.onArrowUp!()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: app.shape.br(24),
              border: Border.all(width: 2, color: borderColor),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
