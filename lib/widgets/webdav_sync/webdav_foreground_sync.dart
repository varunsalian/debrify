import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/player_display_controls.dart';

/// Presentation owns only its wake lock and route, never the sync operation.
/// Hiding/timeout cannot interrupt an adoption or start overlapping work.
Future<T> runWebDavForegroundSync<T>(
  BuildContext context, {
  required String stage,
  String title = 'Syncing with WebDAV',
  required Future<T> Function(ValueChanged<String> updateStage) operation,
  PlayerDisplayControls? displayControls,
  // Setup can legitimately take several minutes; null keeps progress visible.
  Duration? progressLimit = const Duration(seconds: 60),
}) async {
  final progress = ValueNotifier(stage);
  var finished = false;
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ForegroundSyncDialog(
      progress: progress,
      title: title,
      controls: displayControls ?? PlayerDisplayControls.instance,
      progressLimit: progressLimit,
    ),
  );
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(navigator.push(route));
  try {
    return await operation((value) {
      if (!finished) progress.value = value;
    });
  } finally {
    finished = true;
    // A replacement confirmation can be above this route. Never pop it.
    if (route.isActive) route.navigator?.removeRoute(route);
    // Route disposal follows the navigation frame, not operation completion.
    unawaited(route.completed.then((_) => progress.dispose()));
  }
}

class _ForegroundSyncDialog extends StatefulWidget {
  const _ForegroundSyncDialog({
    required this.progress,
    required this.title,
    required this.controls,
    required this.progressLimit,
  });
  final ValueNotifier<String> progress;
  final String title;
  final PlayerDisplayControls controls;
  final Duration? progressLimit;

  @override
  State<_ForegroundSyncDialog> createState() => _ForegroundSyncDialogState();
}

class _ForegroundSyncDialogState extends State<_ForegroundSyncDialog>
    with WidgetsBindingObserver {
  final _wakeOwner = Object();
  Timer? _timer;
  bool _takingLonger = false;
  bool _backgrounded = false;
  bool _returned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _backgrounded = lifecycle != null && lifecycle != AppLifecycleState.resumed;
    _updateWake();
    final progressLimit = widget.progressLimit;
    if (progressLimit != null) {
      _timer = Timer(progressLimit, () {
        setState(() => _takingLonger = true);
      });
    }
  }

  void _updateWake() =>
      unawaited(widget.controls.setWakelockOwner(_wakeOwner, !_backgrounded));

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      final background = state != AppLifecycleState.resumed;
      if (_backgrounded && !background) _returned = true;
      _backgrounded = background;
    });
    _updateWake();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.controls.setWakelockOwner(_wakeOwner, false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _takingLonger
          ? widget.title == 'Syncing with WebDAV'
                ? 'Sync is taking longer'
                : 'Taking longer than expected'
          : widget.title,
    ),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_takingLonger && !_backgrounded) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
        ],
        ValueListenableBuilder<String>(
          valueListenable: widget.progress,
          builder: (_, stage, _) => Text(stage),
        ),
        const SizedBox(height: 12),
        Text(
          _takingLonger
              ? 'Completion has not been confirmed. You can hide this progress; '
                    'the current attempt will continue. Retry after it finishes if needed.'
              : 'Keep Debrify open until this finishes. '
                    'The screen stays awake while this progress is shown.',
        ),
        if (_returned) ...[
          const SizedBox(height: 12),
          const Text(
            'Leaving the app may have interrupted the connection. '
            'Waiting for the current attempt to finish.',
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Minimizing, locking, or closing the app can interrupt sync.',
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Hide progress'),
      ),
    ],
  );
}
