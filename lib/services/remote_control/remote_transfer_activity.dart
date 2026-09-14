import 'dart:async';

import 'package:flutter/foundation.dart';

import '../player_display_controls.dart';

class RemoteTransferActivity {
  const RemoteTransferActivity(
    this.stage, {
    this.completed = 0,
    this.total = 0,
  });
  final String stage;
  final int completed;
  final int total;
  double? get fraction => total > 0 ? (completed / total).clamp(0, 1) : null;
}

/// One activity source for every export UI, independent of UDP heartbeat
/// readiness. An operation keeps its own wake owner until its real outcome.
class RemoteTransferActivityController {
  final ValueNotifier<RemoteTransferActivity?> status = ValueNotifier(null);
  int _operations = 0;
  DateTime? _lastProgress;
  bool get active => _operations > 0;

  Future<void> Function() begin() {
    final owner = Object();
    var released = false;
    _operations++;
    update('Preparing transfer…');
    unawaited(PlayerDisplayControls.instance.setWakelockOwner(owner, true));
    return () async {
      if (released) return;
      released = true;
      await PlayerDisplayControls.instance.setWakelockOwner(owner, false);
      if (--_operations == 0) status.value = null;
    };
  }

  Future<T> run<T>(Future<T> Function() action) async {
    final release = begin();
    try {
      return await action();
    } finally {
      await release();
    }
  }

  void update(String stage) {
    if (active) status.value = RemoteTransferActivity(stage);
  }

  void progress(int done, int total) {
    final now = DateTime.now();
    if (done != total &&
        _lastProgress != null &&
        now.difference(_lastProgress!) < const Duration(milliseconds: 100)) {
      return;
    }
    _lastProgress = now;
    if (active) {
      status.value = done == total
          ? const RemoteTransferActivity('Waiting for the receiving device…')
          : RemoteTransferActivity(
              'Transferring…',
              completed: done,
              total: total,
            );
    }
  }
}
