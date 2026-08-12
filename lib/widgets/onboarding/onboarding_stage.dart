import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme_scope.dart';
import '../../theme/widgets/parallax_focus.dart';
import '../../utils/tv_keys.dart';
import 'onboarding_focus.dart';
import 'onboarding_models.dart';

class OnboardingStage extends StatelessWidget {
  const OnboardingStage({
    super.key,
    required this.step,
    required this.layout,
    required this.focusController,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.content,
    this.footer,
    this.keyStep = false,
    this.backEnabled = true,
  });

  final OnboardStep step;
  final OnboardLayout layout;
  final OnboardFocusController focusController;
  final String eyebrow;
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final Widget content;
  final Widget? footer;
  final bool keyStep;
  final bool backEnabled;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final background = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          app.core.ground.withValues(alpha: 1),
          Color.lerp(
            app.core.ground,
            app.core.pane,
            0.34,
          )!.withValues(alpha: 1),
        ],
      ),
    );
    return DecoratedBox(
      decoration: background,
      child: SafeArea(
        child: switch (layout) {
          OnboardLayout.stage => _buildStage(context),
          OnboardLayout.tablet => _buildCompact(context, tablet: true),
          OnboardLayout.phone => _buildCompact(context, tablet: false),
        },
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    final railWidth = keyStep ? 63.0 : 300.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(42, 48, 42, keyStep ? 0 : 44),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: railWidth,
            child: keyStep
                ? Align(
                    alignment: Alignment.topLeft,
                    child: OnboardBackControl(
                      controller: focusController,
                      onPressed: onBack,
                      enabled: backEnabled,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OnboardBackControl(
                        controller: focusController,
                        onPressed: onBack,
                        enabled: backEnabled,
                      ),
                      const SizedBox(height: 22),
                      _Heading(
                        eyebrow: eyebrow,
                        title: title,
                        subtitle: subtitle,
                      ),
                      const Spacer(),
                      OnboardLadder(step: step),
                    ],
                  ),
          ),
          SizedBox(width: keyStep ? 42 : 42),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: content),
                if (footer != null) ...[const SizedBox(height: 18), footer!],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(BuildContext context, {required bool tablet}) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            tablet ? 28 : 18,
            tablet ? 24 : 16,
            tablet ? 28 : 18,
            14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  OnboardBackControl(
                    controller: focusController,
                    onPressed: onBack,
                    compact: true,
                    enabled: backEnabled,
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: OnboardSegments(step: step)),
                ],
              ),
              if (!keyStep) ...[
                const SizedBox(height: 18),
                _Heading(
                  eyebrow: eyebrow,
                  title: title,
                  subtitle: subtitle,
                  compact: true,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tablet ? 28 : 18),
            child: content,
          ),
        ),
        if (footer != null)
          AnimatedPadding(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.fromLTRB(
              tablet ? 28 : 18,
              12,
              tablet ? 28 : 18,
              (keyStep ? MediaQuery.viewInsetsOf(context).bottom : 0) + 16,
            ),
            child: footer!,
          ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.2,
            color: scheme.onSurface.withValues(alpha: 0.42),
          ),
        ),
        SizedBox(height: compact ? 8 : 11),
        Text(
          title,
          style: TextStyle(
            fontSize: compact ? 27 : 31,
            height: 1.06,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: compact ? 12 : 12.5,
              height: 1.46,
              color: scheme.onSurface.withValues(alpha: 0.60),
            ),
          ),
        ),
      ],
    );
  }
}

class OnboardBackControl extends StatefulWidget {
  const OnboardBackControl({
    super.key,
    required this.controller,
    required this.onPressed,
    this.compact = false,
    this.enabled = true,
  });

  final OnboardFocusController controller;
  final VoidCallback onPressed;
  final bool compact;
  final bool enabled;

  @override
  State<OnboardBackControl> createState() => _OnboardBackControlState();
}

class _OnboardBackControlState extends State<OnboardBackControl> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.controller.backNode.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() => _focused = widget.controller.backNode.hasFocus);
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (!widget.enabled) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      // Let the route-level Back machinery own physical Back. Android may
      // deliver the same press through the navigation channel as well, so
      // activating here would risk moving two steps.
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.controller.returnFromBack();
      return KeyEventResult.handled;
    }
    if (isActivateKey(key) && event is! KeyRepeatEvent) {
      widget.onPressed();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    widget.controller.backNode.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? 42.0 : 33.0;
    final ink = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: 'Back',
      child: Focus(
        focusNode: widget.controller.backNode,
        canRequestFocus: widget.enabled,
        onKeyEvent: _key,
        child: GestureDetector(
          onTap: widget.enabled ? widget.onPressed : null,
          child: RepaintBoundary(
            child: ParallaxFocus(
              focused: _focused,
              shape: ParallaxShape.pill,
              radius: BorderRadius.circular(size / 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: !widget.enabled
                      ? ink.withValues(alpha: 0.04)
                      : _focused
                      ? ink
                      : ink.withValues(alpha: 0.08),
                ),
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: widget.compact ? 21 : 15,
                  color: !widget.enabled
                      ? ink.withValues(alpha: 0.24)
                      : _focused
                      ? Theme.of(context).colorScheme.surface
                      : ink.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardLadder extends StatelessWidget {
  const OnboardLadder({super.key, required this.step});

  final OnboardStep step;

  int get _index => switch (step) {
    OnboardStep.mode || OnboardStep.services || OnboardStep.key => 0,
    OnboardStep.engines => 1,
    OnboardStep.trackers => 2,
    OnboardStep.importing => 0,
    OnboardStep.done => 3,
  };

  @override
  Widget build(BuildContext context) {
    const labels = <String>['Services', 'Search', 'Trackers', 'Ready'];
    final ink = Theme.of(context).colorScheme.onSurface;
    return Column(
      children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5.5),
            child: Row(
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= _index ? ink : Colors.transparent,
                    border: Border.all(
                      color: ink.withValues(alpha: i <= _index ? 1 : 0.24),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == _index ? FontWeight.w600 : FontWeight.w400,
                    color: ink.withValues(alpha: i == _index ? 1 : 0.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class OnboardSegments extends StatelessWidget {
  const OnboardSegments({super.key, required this.step});

  final OnboardStep step;

  @override
  Widget build(BuildContext context) {
    final ladder = OnboardLadder(step: step);
    final index = ladder._index;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(4, (i) {
        return Expanded(
          child: Container(
            height: 3,
            margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: i <= index
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
        );
      }),
    );
  }
}

class OnboardCardSurface extends StatelessWidget {
  const OnboardCardSurface({
    super.key,
    required this.focused,
    required this.child,
    this.selected = false,
    this.padding = const EdgeInsets.all(18),
    this.radius = 11,
  });

  final bool focused;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: scheme.onSurface.withValues(alpha: focused ? 0.15 : 0.055),
        border: Border.all(
          color: selected
              ? scheme.primary.withValues(alpha: 0.72)
              : scheme.onSurface.withValues(alpha: focused ? 0.16 : 0.07),
        ),
      ),
      child: child,
    );
  }
}

class OnboardPillSurface extends StatelessWidget {
  const OnboardPillSurface({
    super.key,
    required this.focused,
    required this.label,
    this.icon,
    this.primary = false,
    this.enabled = true,
  });

  final bool focused;
  final String label;
  final IconData? icon;
  final bool primary;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = focused
        ? scheme.onSurface
        : primary
        ? scheme.onSurface.withValues(alpha: 0.20)
        : scheme.onSurface.withValues(alpha: 0.08);
    final foreground = focused ? scheme.surface : scheme.onSurface;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 21),
      decoration: BoxDecoration(
        color: enabled ? fill : fill.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground.withValues(alpha: enabled ? 1 : 0.45),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
