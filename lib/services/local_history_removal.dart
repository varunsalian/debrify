import 'dart:async';

/// One accepted removal includes its history, position and recovery records.
/// Once started, the writer finishes in its captured scope; retirement suppresses
/// presentation feedback, not the second half of an accepted deletion.
class LocalHistoryRemoval {
  const LocalHistoryRemoval({
    required this.write,
    required this.isOwnerCurrent,
  });

  // Shared with the profile lifecycle: callbacks belong to accepted operations,
  // not to the view/provider that initiated them. Failures stay with the caller.
  static final _pending = <Future<void>>{};

  /// Retire views first. Never hold a preference snapshot barrier while draining.
  static Future<void> drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }

  final Future<void> Function(String) write;
  final bool Function() isOwnerCurrent;

  Future<bool> remove(String id, {required bool Function() isCurrent}) async {
    if (id.trim().isEmpty || !isOwnerCurrent() || !isCurrent()) return false;
    final completed = Completer<void>();
    _pending.add(completed.future);
    try {
      await write(id);
      return isOwnerCurrent() && isCurrent();
    } finally {
      _pending.remove(completed.future);
      completed.complete();
    }
  }
}
