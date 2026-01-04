import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// A widget that wraps its child and adds window drag + double-click to maximize/restore functionality.
/// Only active on Windows desktop. On other platforms, it just returns the child as-is.
class WindowDragArea extends StatefulWidget {
  final Widget child;

  const WindowDragArea({super.key, required this.child});

  @override
  State<WindowDragArea> createState() => _WindowDragAreaState();
}

class _WindowDragAreaState extends State<WindowDragArea> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && Platform.isWindows) {
      windowManager.addListener(this);
      _checkMaximized();
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && Platform.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _checkMaximized() async {
    if (!kIsWeb && Platform.isWindows) {
      final maximized = await windowManager.isMaximized();
      if (mounted && maximized != _isMaximized) {
        setState(() => _isMaximized = maximized);
      }
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only apply on Windows
    if (kIsWeb || !Platform.isWindows) {
      return widget.child;
    }

    final tooltipMessage = _isMaximized
        ? 'Double-click to restore'
        : 'Double-click to maximize';

    return Tooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: _toggleMaximize,
        child: widget.child,
      ),
    );
  }
}
