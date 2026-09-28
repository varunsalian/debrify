import 'dart:async';

/// Tracks accepted local write sequences through profile handoff. Callers must
/// validate acceptance and capture their storage scope before entering [run].
/// This is a drain, not a lock: do not hold a preference snapshot while awaiting it.
class ProfileLocalWrites {
  ProfileLocalWrites._();
  static final _pending = <Future<void>>{};

  static Future<T> run<T>(Future<T> Function() write) async {
    final completed = Completer<void>();
    _pending.add(completed.future);
    try {
      return await write();
    } finally {
      _pending.remove(completed.future);
      // A failed writer reports to its caller without stranding profile handoff.
      completed.complete();
    }
  }

  /// Retire outgoing actions first, then drain before publishing the next profile.
  static Future<void> drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }
}
