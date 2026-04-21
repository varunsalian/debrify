import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/main_page_bridge.dart';
import 'home_focus_controller.dart';

class HomeEmptyAction {
  const HomeEmptyAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onActivate,
    this.accentColor = const Color(0xFF8B5CF6),
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final FutureOr<void> Function() onActivate;
  final Color accentColor;
}

class HomeEmptyState extends StatefulWidget {
  const HomeEmptyState({
    super.key,
    required this.focusController,
    required this.isTelevision,
    required this.isEmptyCandidate,
    required this.onRequestFocusAbove,
    required this.actions,
  });

  final HomeFocusController focusController;
  final bool isTelevision;
  final bool isEmptyCandidate;
  final VoidCallback onRequestFocusAbove;
  final List<HomeEmptyAction> actions;

  @override
  State<HomeEmptyState> createState() => _HomeEmptyStateState();
}

class _HomeEmptyStateState extends State<HomeEmptyState> {
  static const Duration _revealDelay = Duration(milliseconds: 900);

  final List<FocusNode> _focusNodes = [];
  Timer? _revealTimer;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _syncFocusNodes();
    _syncRevealState();
  }

  @override
  void didUpdateWidget(HomeEmptyState oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actions.length != widget.actions.length) {
      _syncFocusNodes();
    }
    if (oldWidget.isEmptyCandidate != widget.isEmptyCandidate ||
        oldWidget.actions.length != widget.actions.length) {
      _syncRevealState();
    } else {
      _updateRegistration();
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    widget.focusController.unregisterSection(HomeSection.emptyState);
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncFocusNodes() {
    while (_focusNodes.length < widget.actions.length) {
      _focusNodes.add(
        FocusNode(debugLabel: 'home-empty-action-${_focusNodes.length}'),
      );
    }
    while (_focusNodes.length > widget.actions.length) {
      _focusNodes.removeLast().dispose();
    }
  }

  void _syncRevealState() {
    _revealTimer?.cancel();

    if (!widget.isEmptyCandidate || widget.actions.isEmpty) {
      if (_revealed) {
        setState(() => _revealed = false);
      }
      _updateRegistration();
      return;
    }

    if (_revealed) {
      _updateRegistration();
      return;
    }

    _revealTimer = Timer(_revealDelay, () {
      if (!mounted || !widget.isEmptyCandidate || widget.actions.isEmpty) {
        return;
      }
      setState(() => _revealed = true);
      _updateRegistration();
    });
  }

  void _updateRegistration() {
    final visible =
        _revealed && widget.isEmptyCandidate && widget.actions.isNotEmpty;
    widget.focusController.registerSection(
      HomeSection.emptyState,
      hasItems: visible,
      focusNodes: visible ? _focusNodes : const [],
    );
  }

  void _handleFocusChange(bool focused, int index) {
    if (!focused) return;

    widget.focusController.saveLastFocusedIndex(HomeSection.emptyState, index);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _focusNodes[index].context;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.18,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  KeyEventResult _handleKeyEvent(KeyEvent event, int index, int columns) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      widget.actions[index].onActivate();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      final nextIndex = index - columns;
      if (nextIndex >= 0) {
        _focusNodes[nextIndex].requestFocus();
      } else {
        widget.onRequestFocusAbove();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      final nextIndex = index + columns;
      if (nextIndex < _focusNodes.length) {
        _focusNodes[nextIndex].requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (columns > 1) {
        final isLeftColumn = index % columns == 0;
        if (!isLeftColumn) {
          _focusNodes[index - 1].requestFocus();
        } else if (widget.isTelevision) {
          MainPageBridge.focusTvSidebar?.call();
        }
        return KeyEventResult.handled;
      }
      if (widget.isTelevision) {
        MainPageBridge.focusTvSidebar?.call();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (columns > 1 && key == LogicalKeyboardKey.arrowRight) {
      final isRightColumn = index % columns == columns - 1;
      final nextIndex = index + 1;
      if (!isRightColumn && nextIndex < _focusNodes.length) {
        _focusNodes[nextIndex].requestFocus();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!_revealed || !widget.isEmptyCandidate || widget.actions.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF151630), Color(0xFF0B1020)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -30,
              right: -20,
              child: _GlowOrb(
                size: 160,
                color: const Color(0xFF22C55E).withValues(alpha: 0.12),
              ),
            ),
            Positioned(
              bottom: -36,
              left: -12,
              child: _GlowOrb(
                size: 180,
                color: const Color(0xFF38BDF8).withValues(alpha: 0.10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Text(
                      'HOME BUILDS ITSELF',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Nothing here yet',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Watch something to start Continue Watching, connect Trakt for calendar and progress, save items to Playlist, or favorite Debrify TV channels. Home fills in as you use the app.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.72),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 720 ? 2 : 1;
                      final spacing = 12.0;
                      final tileWidth = columns == 1
                          ? constraints.maxWidth
                          : (constraints.maxWidth - spacing) / 2;

                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: List.generate(widget.actions.length, (index) {
                          final action = widget.actions[index];
                          return SizedBox(
                            width: tileWidth,
                            child: _HomeEmptyActionCard(
                              action: action,
                              focusNode: _focusNodes[index],
                              isTelevision: widget.isTelevision,
                              onFocusChange: (focused) =>
                                  _handleFocusChange(focused, index),
                              onKeyEvent: (event) =>
                                  _handleKeyEvent(event, index, columns),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeEmptyActionCard extends StatefulWidget {
  const _HomeEmptyActionCard({
    required this.action,
    required this.focusNode,
    required this.isTelevision,
    required this.onFocusChange,
    required this.onKeyEvent,
  });

  final HomeEmptyAction action;
  final FocusNode focusNode;
  final bool isTelevision;
  final ValueChanged<bool> onFocusChange;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;

  @override
  State<_HomeEmptyActionCard> createState() => _HomeEmptyActionCardState();
}

class _HomeEmptyActionCardState extends State<_HomeEmptyActionCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = _focused || _hovered;
    final accent = widget.action.accentColor;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        widget.onFocusChange(focused);
        setState(() => _focused = focused);
      },
      onKeyEvent: (_, event) => widget.onKeyEvent(event),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => widget.action.onActivate(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isActive ? accent : Colors.white.withValues(alpha: 0.08),
                width: isActive ? 2 : 1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.07),
                  accent.withValues(alpha: isActive ? 0.16 : 0.10),
                ],
              ),
              boxShadow: widget.isTelevision || !isActive
                  ? null
                  : [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.20),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 360;

                final iconBadge = Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(widget.action.icon, color: accent, size: 24),
                );

                final titleText = Text(
                  widget.action.title,
                  maxLines: isCompact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                );

                final subtitleText = Text(
                  widget.action.subtitle,
                  maxLines: isCompact ? 4 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                );

                final trailingArrow = Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white.withValues(alpha: 0.48),
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          iconBadge,
                          const SizedBox(width: 14),
                          Expanded(child: titleText),
                          const SizedBox(width: 8),
                          trailingArrow,
                        ],
                      ),
                      const SizedBox(height: 12),
                      subtitleText,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconBadge,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          titleText,
                          const SizedBox(height: 4),
                          subtitleText,
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: trailingArrow,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent]),
        ),
      ),
    );
  }
}
