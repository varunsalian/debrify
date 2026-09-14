import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../services/player_visibility.dart';
import '../../services/webdav_sync/webdav_sync_save_feedback.dart';

/// Quiet sender-only activity feedback; remote reads create no local receipt.
class WebDavSaveStatus extends StatefulWidget {
  const WebDavSaveStatus({super.key, required this.child, this.feedback});
  final Widget child;
  final WebDavSyncSaveFeedback? feedback;
  @override
  State<WebDavSaveStatus> createState() => _WebDavSaveStatusState();
}

class _WebDavSaveStatusState extends State<WebDavSaveStatus> {
  Timer? _visibilityTimer;
  bool _syncing = false;
  bool _expired = false;

  void _updateActivity() {
    final syncing =
        feedback.enabled && feedback.phase == WebDavSavePhase.syncing;
    if (syncing == _syncing) return;
    _syncing = syncing;
    _visibilityTimer?.cancel();
    _expired = false;
    if (syncing) {
      // One budget per continuous activity episode, not per notification.
      // Playback and rebuilds must not restart this deadline.
      _visibilityTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) setState(() => _expired = true);
      });
    }
  }

  WebDavSyncSaveFeedback get feedback =>
      widget.feedback ?? WebDavSyncSaveFeedback.instance;

  @override
  void initState() {
    super.initState();
    feedback.addListener(_changed);
    PlayerVisibility.visible.addListener(_changed);
    _updateActivity();
  }

  @override
  void didUpdateWidget(covariant WebDavSaveStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFeedback = oldWidget.feedback ?? WebDavSyncSaveFeedback.instance;
    if (oldFeedback != feedback) {
      oldFeedback.removeListener(_changed);
      feedback.addListener(_changed);
      _updateActivity();
    }
  }

  void _changed() {
    _updateActivity();
    // Player routes may acquire/release visibility during build/dispose.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _visibilityTimer?.cancel();
    feedback.removeListener(_changed);
    PlayerVisibility.visible.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        feedback.enabled &&
        !_expired &&
        !PlayerVisibility.visible.value &&
        feedback.phase == WebDavSavePhase.syncing;
    return Stack(
      children: [
        widget.child,
        if (visible)
          Positioned(
            right: 20,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
            child: const SafeArea(child: IgnorePointer(child: _SyncDot())),
          ),
      ],
    );
  }
}

class _SyncDot extends StatefulWidget {
  const _SyncDot();

  @override
  State<_SyncDot> createState() => _SyncDotState();
}

class _SyncDotState extends State<_SyncDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.3,
    end: 1,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Syncing to WebDAV',
    child: FadeTransition(
      opacity: _opacity,
      child: const SizedBox(
        key: ValueKey('webdav-sync-dot'),
        width: 6,
        height: 6,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF88DDC5),
            boxShadow: [
              BoxShadow(
                color: Color(0x5588DDC5),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
