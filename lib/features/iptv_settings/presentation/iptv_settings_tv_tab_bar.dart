import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV-focusable tab bar with DPAD navigation
class IptvSettingsTvTabBar extends StatefulWidget {
  const IptvSettingsTvTabBar({
    required this.tabController,
    required this.urlTabFocusNode,
    required this.fileTabFocusNode,
    this.xcTabFocusNode,
    this.onUpArrow,
    this.onDownArrowFromUrlTab,
    this.onDownArrowFromFileTab,
    this.onDownArrowFromXcTab,
  });

  final TabController tabController;
  final FocusNode urlTabFocusNode;
  final FocusNode fileTabFocusNode;
  final FocusNode? xcTabFocusNode;
  final VoidCallback? onUpArrow;
  final VoidCallback? onDownArrowFromUrlTab;
  final VoidCallback? onDownArrowFromFileTab;
  final VoidCallback? onDownArrowFromXcTab;

  @override
  State<IptvSettingsTvTabBar> createState() => _TvFocusableTabBarState();
}

class _TvFocusableTabBarState extends State<IptvSettingsTvTabBar> {
  bool _urlTabFocused = false;
  bool _fileTabFocused = false;
  bool _xcTabFocused = false;

  @override
  void initState() {
    super.initState();
    widget.urlTabFocusNode.addListener(_onUrlTabFocusChange);
    widget.fileTabFocusNode.addListener(_onFileTabFocusChange);
    widget.xcTabFocusNode?.addListener(_onXcTabFocusChange);
  }

  @override
  void dispose() {
    widget.urlTabFocusNode.removeListener(_onUrlTabFocusChange);
    widget.fileTabFocusNode.removeListener(_onFileTabFocusChange);
    widget.xcTabFocusNode?.removeListener(_onXcTabFocusChange);
    super.dispose();
  }

  void _onUrlTabFocusChange() {
    if (mounted) {
      setState(() => _urlTabFocused = widget.urlTabFocusNode.hasFocus);
    }
  }

  void _onFileTabFocusChange() {
    if (mounted) {
      setState(() => _fileTabFocused = widget.fileTabFocusNode.hasFocus);
    }
  }

  void _onXcTabFocusChange() {
    if (mounted) {
      setState(() => _xcTabFocused = widget.xcTabFocusNode?.hasFocus ?? false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: app.shape.br(12),
        border: Border.all(color: t.line),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          // URL Tab
          Expanded(
            child: FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: Focus(
                focusNode: widget.urlTabFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;

                  if (isActivateKey(event.logicalKey)) {
                    // OK selects the tab AND enters its form — after OK the
                    // user's next instinct is to continue downward.
                    widget.tabController.animateTo(0);
                    widget.onDownArrowFromUrlTab?.call();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    widget.fileTabFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                      widget.onUpArrow != null) {
                    widget.onUpArrow!();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                      widget.onDownArrowFromUrlTab != null) {
                    widget.tabController.animateTo(0);
                    widget.onDownArrowFromUrlTab!();
                    return KeyEventResult.handled;
                  }

                  return KeyEventResult.ignored;
                },
                child: GestureDetector(
                  onTap: () => widget.tabController.animateTo(0),
                  child: AnimatedBuilder(
                    animation: widget.tabController,
                    builder: (context, child) {
                      final isSelected = widget.tabController.index == 0;
                      // Snap, don't tween — TV GPU rule.
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? t.accent.withValues(alpha: 0.22)
                              : Colors.transparent,
                          borderRadius: app.shape.br(8),
                          border: _urlTabFocused
                              ? Border.all(color: t.accent, width: 2)
                              : null,
                          boxShadow: _urlTabFocused
                              ? [
                                  BoxShadow(
                                    color: t.accent.withValues(alpha: 0.3),
                                    blurRadius: 4,
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.link,
                              size: 18,
                              color: isSelected ? t.accent2 : t.dim,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'From URL',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isSelected ? app.core.tx : t.dim,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // File Tab
          Expanded(
            child: FocusTraversalOrder(
              order: const NumericFocusOrder(1.5),
              child: Focus(
                focusNode: widget.fileTabFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;

                  if (isActivateKey(event.logicalKey)) {
                    // OK = select + enter the form (see the URL tab).
                    widget.tabController.animateTo(1);
                    widget.onDownArrowFromFileTab?.call();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    widget.urlTabFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                      widget.xcTabFocusNode != null) {
                    widget.xcTabFocusNode!.requestFocus();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                      widget.onUpArrow != null) {
                    widget.onUpArrow!();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                      widget.onDownArrowFromFileTab != null) {
                    widget.tabController.animateTo(1);
                    widget.onDownArrowFromFileTab!();
                    return KeyEventResult.handled;
                  }

                  return KeyEventResult.ignored;
                },
                child: GestureDetector(
                  onTap: () => widget.tabController.animateTo(1),
                  child: AnimatedBuilder(
                    animation: widget.tabController,
                    builder: (context, child) {
                      final isSelected = widget.tabController.index == 1;
                      // Snap, don't tween — TV GPU rule.
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? t.accent.withValues(alpha: 0.22)
                              : Colors.transparent,
                          borderRadius: app.shape.br(8),
                          border: _fileTabFocused
                              ? Border.all(color: t.accent, width: 2)
                              : null,
                          boxShadow: _fileTabFocused
                              ? [
                                  BoxShadow(
                                    color: t.accent.withValues(alpha: 0.3),
                                    blurRadius: 4,
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              size: 18,
                              color: isSelected ? t.accent2 : t.dim,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'From File',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isSelected ? app.core.tx : t.dim,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          // Xtream Codes Tab
          if (widget.xcTabFocusNode != null) ...[
            const SizedBox(width: 4),
            Expanded(
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(1.75),
                child: Focus(
                  focusNode: widget.xcTabFocusNode,
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;

                    if (isActivateKey(event.logicalKey)) {
                      // OK = select + enter the form (see the URL tab).
                      widget.tabController.animateTo(2);
                      widget.onDownArrowFromXcTab?.call();
                      return KeyEventResult.handled;
                    }

                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      widget.fileTabFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    }

                    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                        widget.onUpArrow != null) {
                      widget.onUpArrow!();
                      return KeyEventResult.handled;
                    }

                    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                        widget.onDownArrowFromXcTab != null) {
                      widget.tabController.animateTo(2);
                      widget.onDownArrowFromXcTab!();
                      return KeyEventResult.handled;
                    }

                    return KeyEventResult.ignored;
                  },
                  child: GestureDetector(
                    onTap: () => widget.tabController.animateTo(2),
                    child: AnimatedBuilder(
                      animation: widget.tabController,
                      builder: (context, child) {
                        final isSelected = widget.tabController.index == 2;
                        // Snap, don't tween — TV GPU rule.
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? t.accent.withValues(alpha: 0.22)
                                : Colors.transparent,
                            borderRadius: app.shape.br(8),
                            border: _xcTabFocused
                                ? Border.all(color: t.accent, width: 2)
                                : null,
                            boxShadow: _xcTabFocused
                                ? [
                                    BoxShadow(
                                      color: t.accent.withValues(alpha: 0.3),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.login,
                                size: 18,
                                color: isSelected ? t.accent2 : t.dim,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Xtream Login',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: isSelected ? app.core.tx : t.dim,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
