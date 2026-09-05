import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/webdav_sync/webdav_sync_save_feedback.dart';

/// Global sender-only feedback; remote reads never create a local receipt.
class WebDavSaveStatus extends StatefulWidget {
  const WebDavSaveStatus({super.key, required this.child, this.feedback});
  final Widget child;
  final WebDavSyncSaveFeedback? feedback;
  @override
  State<WebDavSaveStatus> createState() => _WebDavSaveStatusState();
}

class _WebDavSaveStatusState extends State<WebDavSaveStatus> {
  WebDavSyncSaveFeedback get feedback =>
      widget.feedback ?? WebDavSyncSaveFeedback.instance;
  Timer? _successTimer;
  bool _hideSuccess = false;
  @override
  void initState() {
    super.initState();
    feedback.addListener(_changed);
  }

  void _changed() {
    _successTimer?.cancel();
    _hideSuccess = false;
    if (feedback.phase == WebDavSavePhase.synced) {
      _successTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _hideSuccess = true);
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    feedback.removeListener(_changed);
    _successTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = feedback.phase;
    final visible =
        feedback.enabled && phase != WebDavSavePhase.inactive && !_hideSuccess;
    return Stack(
      children: [
        widget.child,
        if (visible)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: Align(
                alignment: Alignment.bottomRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          if (phase == WebDavSavePhase.syncing)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              phase == WebDavSavePhase.synced
                                  ? Icons.cloud_done_outlined
                                  : Icons.cloud_upload_outlined,
                              size: 20,
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                phase == WebDavSavePhase.synced
                                    ? 'Synced to WebDAV'
                                    : feedback.takingLonger
                                    ? 'Sync is taking longer. Your change is saved locally.'
                                    : phase == WebDavSavePhase.syncing
                                    ? 'Saved locally · Syncing to WebDAV…'
                                    : 'Saved locally · Sync pending',
                              ),
                            ),
                          ),
                          if (phase == WebDavSavePhase.pending)
                            TextButton(
                              onPressed: () => unawaited(feedback.retry()),
                              child: const Text('Retry'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Call only after a successful local profile mutation. Timeout never cancels
/// transport work or changes the result of the local save.
Future<void> showWebDavSaveProgress(
  BuildContext context,
  int beforeRevision, {
  WebDavSyncSaveFeedback? feedback,
}) async {
  final source = feedback ?? WebDavSyncSaveFeedback.instance;
  if (!context.mounted ||
      !source.enabled ||
      source.revision <= beforeRevision ||
      !source.hasPending ||
      source.phase == WebDavSavePhase.pending) {
    return;
  }
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SaveProgress(feedback: source, target: source.revision),
    );
  } catch (_) {
    // Presentation must never turn a completed local save into a save error.
  }
}

class _SaveProgress extends StatefulWidget {
  const _SaveProgress({required this.feedback, required this.target});
  final WebDavSyncSaveFeedback feedback;
  final int target;
  @override
  State<_SaveProgress> createState() => _SaveProgressState();
}

class _SaveProgressState extends State<_SaveProgress> {
  Timer? _timer;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    widget.feedback.addListener(_changed);
    _timer = Timer(const Duration(seconds: 15), () {
      widget.feedback.timedOut();
      _close();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  void _changed() {
    if (!widget.feedback.enabled ||
        widget.feedback.confirmedRevision >= widget.target ||
        widget.feedback.phase == WebDavSavePhase.pending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  void _close() {
    if (!mounted || _closing) return;
    _closing = true;
    final route = ModalRoute.of(context);
    // Remove this exact dialog, never a route pushed above it meanwhile.
    if (route != null) route.navigator?.removeRoute(route);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.feedback.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Syncing to WebDAV…'),
    content: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(),
        SizedBox(height: 16),
        Text(
          'Your change is saved locally. Keep the app open to finish uploading.',
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _close,
        child: const Text('Continue in background'),
      ),
    ],
  );
}
