import 'package:debrify/theme/app_theme_scope.dart';

import 'package:debrify/utils/tv_keys.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tab button with DPAD focus support.
class _SourcePickerTab extends StatefulWidget {
  final FocusNode? focusNode;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onDownPress;

  const _SourcePickerTab({
    this.focusNode,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.onDownPress,
  });

  @override
  State<_SourcePickerTab> createState() => _SourcePickerTabState();
}

class _SourcePickerTabState extends State<StremioTvSourcePickerTab> {
  bool _focused = false;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (isActivateKey(event.logicalKey)) {
      widget.onTap();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.onDownPress?.call();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled; // consume — nothing above tabs
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            // Active = purple fill, focus = white ring (Home mode-toggle
            // pattern); the ring shows even on the active pill.
            color: widget.isActive ? app.home.chromeAccent : Colors.transparent,
            borderRadius: app.shape.br(20),
            border: Border.all(
              color: _focused
                  ? app.stremioTv.focusRing
                  : widget.isActive
                  ? Colors.transparent
                  : app.core.tx.withAlpha(0x1F),
              width: _focused ? 2 : 1,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isActive
                  ? app.inkOn(app.home.chromeAccent)
                  : app.core.tx.withAlpha(0x8A),
              fontSize: 13,
              fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// Individual source item with DPAD focus support.
class _SourcePickerItem extends StatefulWidget {
  final FocusNode? focusNode;
  final String quality;
  final Color qualityColor;
  final String title;
  final String meta;
  final bool isResolving;
  final bool isFailed;
  final VoidCallback? onTap;
  final bool isFirst; // first item in list — up arrow goes to tabs
  final VoidCallback? onUpToTabs;

  const _SourcePickerItem({
    this.focusNode,
    required this.quality,
    required this.qualityColor,
    required this.title,
    required this.meta,
    required this.isResolving,
    this.isFailed = false,
    this.onTap,
    this.isFirst = false,
    this.onUpToTabs,
  });

  @override
  State<_SourcePickerItem> createState() => _SourcePickerItemState();
}

class _SourcePickerItemState extends State<StremioTvSourcePickerItem> {
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (isActivateKey(event.logicalKey)) {
      widget.onTap?.call();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.isFirst) {
      widget.onUpToTabs?.call();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final qColor = widget.qualityColor;
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _focused
                ? app.home.chromeAccent.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: app.shape.br(10),
            border: Border.all(
              // Chrome focus ring (width 2), matching the reskinned toggles /
              // header buttons so every DPAD-focusable control reads the same.
              color: _focused ? app.stremioTv.focusRing : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              // Quality badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: qColor.withValues(alpha: 0.15),
                  borderRadius: app.shape.br(6),
                  border: Border.all(color: qColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  widget.quality,
                  style: TextStyle(
                    color: qColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Title + meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _focused
                            ? app.core.tx
                            : app.core.tx.withAlpha(0xB3),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.meta,
                      style: TextStyle(
                        color: app.core.tx.withAlpha(0x62),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Loading, failed, or play icon
              if (widget.isResolving)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: app.home.chromeAccent,
                  ),
                )
              else if (widget.isFailed)
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFEF5350),
                  size: 22,
                )
              else
                Icon(
                  Icons.play_circle_outline,
                  color: _focused
                      ? app.core.tx.withAlpha(0x8A)
                      : app.core.tx.withAlpha(0x3D),
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef StremioTvSourcePickerTab = _SourcePickerTab;
typedef StremioTvSourcePickerItem = _SourcePickerItem;

StremioTvSourcePickerTab stremioTvSourcePickerTab({
  FocusNode? focusNode,
  required String label,
  required bool isActive,
  required VoidCallback onTap,
  VoidCallback? onDownPress,
}) => _SourcePickerTab(
  focusNode: focusNode,
  label: label,
  isActive: isActive,
  onTap: onTap,
  onDownPress: onDownPress,
);
StremioTvSourcePickerItem stremioTvSourcePickerItem({
  FocusNode? focusNode,
  required String quality,
  required Color qualityColor,
  required String title,
  required String meta,
  required bool isResolving,
  bool isFailed = false,
  VoidCallback? onTap,
  bool isFirst = false,
  VoidCallback? onUpToTabs,
}) => _SourcePickerItem(
  focusNode: focusNode,
  quality: quality,
  qualityColor: qualityColor,
  title: title,
  meta: meta,
  isResolving: isResolving,
  isFailed: isFailed,
  onTap: onTap,
  isFirst: isFirst,
  onUpToTabs: onUpToTabs,
);
