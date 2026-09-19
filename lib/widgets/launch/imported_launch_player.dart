import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../services/launch_animation/launch_animation_library.dart';

/// Shared by launch and preview. Owns no files, controller or decoded images.
/// The owner keeps them alive until this widget is detached.
class ImportedLaunchPlayer extends StatefulWidget {
  const ImportedLaunchPlayer({
    super.key,
    required this.animation,
    required this.progress,
    required this.onError,
    this.onWarning,
  });
  final LoadedLaunchAnimation animation;
  final Animation<double> progress;
  final void Function(Object error) onError;
  final ValueChanged<String>? onWarning;
  @override
  State<ImportedLaunchPlayer> createState() => _ImportedLaunchPlayerState();
}

class _ImportedLaunchPlayerState extends State<ImportedLaunchPlayer> {
  _ImportedPainter? _painter;
  LottieComposition? _composition;
  bool _reported = false;
  final ValueNotifier<double> _paintProgress = ValueNotifier(0);
  @override
  void initState() {
    super.initState();
    widget.progress.addListener(_tick);
  }

  @override
  void didUpdateWidget(ImportedLaunchPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      oldWidget.progress.removeListener(_tick);
      widget.progress.addListener(_tick);
    }
    if (oldWidget.animation != widget.animation ||
        oldWidget.progress != widget.progress) {
      _composition?.onWarning = null;
      _composition = null;
    }
  }

  void _report(Object error) {
    if (_reported) return;
    _reported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onError(error);
    });
  }

  void _create(LottieComposition composition) {
    _composition?.onWarning = null;
    _composition = composition;
    _reported = false;
    composition.onWarning = _warn;
    try {
      _painter = _ImportedPainter(
        LottieDrawable(composition),
        _paintProgress,
        _report,
      );
      _tick();
      for (final warning in composition.warnings) {
        _warn(warning);
      }
    } catch (error) {
      _painter = null;
      _report(error);
    }
  }

  void _tick() {
    try {
      final composition = _composition;
      if (composition == null) return;
      _paintProgress.value = composition.roundProgress(
        widget.progress.value,
        frameRate: FrameRate.composition,
      );
    } catch (error) {
      _report(error);
    }
  }

  void _warn(String warning) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onWarning?.call(warning);
    });
  }

  @override
  void dispose() {
    widget.progress.removeListener(_tick);
    _paintProgress.dispose();
    _composition?.onWarning = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final composition = widget.animation.compositionFor(
        constraints.maxHeight > constraints.maxWidth,
      );
      if (_composition != composition) _create(composition);
      return ColoredBox(
        color: Color(widget.animation.background),
        child: RepaintBoundary(
          child: CustomPaint(painter: _painter, child: const SizedBox.expand()),
        ),
      );
    },
  );
}

class _ImportedPainter extends CustomPainter {
  _ImportedPainter(this.drawable, this.progress, this.onError)
    : super(repaint: progress);
  final LottieDrawable drawable;
  final ValueNotifier<double> progress;
  final void Function(Object) onError;
  bool failed = false;
  @override
  void paint(Canvas canvas, Size size) {
    if (failed) return;
    final count = canvas.getSaveCount();
    canvas.save();
    try {
      canvas.clipRect(Offset.zero & size);
      drawable.setProgress(progress.value);
      drawable.draw(
        canvas,
        Offset.zero & size,
        fit: BoxFit.contain,
        alignment: Alignment.center,
      );
    } catch (error) {
      failed = true;
      onError(error);
    } finally {
      canvas.restoreToCount(count);
    }
  }

  @override
  bool shouldRepaint(_ImportedPainter oldDelegate) =>
      drawable != oldDelegate.drawable || progress != oldDelegate.progress;
}
