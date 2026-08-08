import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import '../../widgets/launch/launch_ident.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// Launch ident picker (`launch_animation`).
///
/// The preview at the top plays the selected ident's REAL painter — the same
/// CustomPainter the splash runs, on the same TV/phone quality path this
/// device would use — looping with a short hold, so what you pick is exactly
/// what you get on the next launch.
class LaunchAnimationPage extends StatefulWidget {
  const LaunchAnimationPage({super.key});

  @override
  State<LaunchAnimationPage> createState() => _LaunchAnimationPageState();
}

class _LaunchAnimationPageState extends State<LaunchAnimationPage> {
  // Sync-cached (warmed in main), so no loading state.
  LaunchIdent _choice = launchIdentFor(StorageService.launchAnimationCached);

  /// Non-focusable marker around the options card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'launch-anim-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('launch_animation_settings');
    if (PlatformUtil.isAndroidTvCached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Don't yank focus if it already landed on a real node (only the
        // route's FocusScope holds focus while nothing is focused yet).
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        _firstCardMarker.traversalDescendants.firstOrNull?.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _select(LaunchIdent choice) async {
    if (choice.id == _choice.id) return;
    setState(() => _choice = choice);
    await StorageService.setLaunchAnimation(choice.id);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'Launch Animation',
      // The split exists for DPAD: in one column the list scrolls the preview
      // off the top exactly when you start walking the options, so you choose
      // an ident you can no longer see. Pinning the preview beside the list
      // keeps the thing being chosen on screen for the whole walk.
      //
      // TV takes it unconditionally — that is the surface with the problem,
      // and a 720p box reports only ~640 logical px, which no sane width
      // threshold would catch. Everywhere else it needs room to be worth it:
      // decisively landscape and wide enough for two usable panes, which
      // covers desktop and tablet windows and leaves phones stacked.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final twoPane = PlatformUtil.isAndroidTvCached ||
              (constraints.maxWidth >= 820 &&
                  constraints.maxWidth > constraints.maxHeight * 1.2);
          return twoPane ? _buildTwoPane() : _buildStacked();
        },
      ),
    );
  }

  Widget _buildStacked() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 18),
              _LaunchPreview(ident: _choice),
              const SizedBox(height: 18),
              _optionsCard(),
              const SizedBox(height: 14),
              _footnote(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTwoPane() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The only focusable pane. Scrolls on its own, so a longer ident
          // list never moves the preview.
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  const SizedBox(height: 18),
                  _optionsCard(),
                  const SizedBox(height: 14),
                  _footnote(),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Pinned preview. Nothing here can take focus, so LEFT/RIGHT keep
          // the DPAD inside the list instead of stranding it on a picture.
          Expanded(
            flex: 6,
            child: Center(child: _LaunchPreview(ident: _choice)),
          ),
        ],
      ),
    );
  }

  Widget _header() => const SettingsPageHeader(
        icon: Icons.rocket_launch_rounded,
        title: 'Launch Animation',
        subtitle: 'The ident Debrify plays while it starts',
      );

  Widget _optionsCard() => Focus(
        focusNode: _firstCardMarker,
        canRequestFocus: false,
        skipTraversal: true,
        child: SettingsSection(
          title: '',
          children: [
            for (final ident in kLaunchIdents) _optionRow(ident),
          ],
        ),
      );

  Widget _footnote() => Text(
        'The preview runs the real splash painter on this device\'s quality '
        'path. Your pick plays on the next launch.',
        style: TextStyle(
          fontSize: 12.5,
          height: 1.45,
          color: AppThemeScope.of(context).settings.dim,
        ),
      );

  /// Radio-style row — a plain [SettingsTile] (the DPAD-proven row) with a
  /// check on the active one.
  Widget _optionRow(LaunchIdent ident) {
    final t = AppThemeScope.of(context).settings;
    final bool active = _choice.id == ident.id;
    return SettingsTile(
      icon: active
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_unchecked_rounded,
      title: ident.label,
      subtitle: ident.subtitle,
      trailing: active
          ? Icon(Icons.check_rounded, size: 20, color: t.accent2)
          : const SizedBox.shrink(),
      onTap: () => _select(ident),
    );
  }
}

/// Loops the selected ident's real painter: play → hold 1.4 s → replay.
class _LaunchPreview extends StatefulWidget {
  final LaunchIdent ident;
  const _LaunchPreview({required this.ident});

  @override
  State<_LaunchPreview> createState() => _LaunchPreviewState();
}

class _LaunchPreviewState extends State<_LaunchPreview>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  CustomPainter? _painter;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant _LaunchPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ident.id != widget.ident.id) _start();
  }

  void _start() {
    _holdTimer?.cancel();
    _controller?.dispose();
    final c = AnimationController(
      duration: widget.ident.revealDuration,
      vsync: this,
    );
    _controller = c;
    _painter = widget.ident.createPainter(
      c,
      isTelevision: () => PlatformUtil.isAndroidTvCached,
    );
    c.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _holdTimer = Timer(const Duration(milliseconds: 1400), () {
          if (mounted && identical(_controller, c)) c.forward(from: 0);
        });
      }
    });
    c.forward();
    setState(() {});
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          // The ident's static backdrop, exactly as the splash composes it —
          // the painter draws only the moving elements over it.
          decoration: widget.ident.backdrop,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _painter,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}
