import 'profiles/profile_local_writes.dart';

/// One accepted removal includes its history, position and recovery records.
/// Once started, the writer finishes in its captured scope; retirement suppresses
/// presentation feedback, not the second half of an accepted deletion.
class LocalHistoryRemoval {
  const LocalHistoryRemoval({
    required this.write,
    required this.isOwnerCurrent,
  });

  /// Compatibility entry point for accepted history operations.
  static Future<void> drain() => ProfileLocalWrites.drain();

  final Future<void> Function(String) write;
  final bool Function() isOwnerCurrent;

  Future<bool> remove(String id, {required bool Function() isCurrent}) async {
    if (id.trim().isEmpty || !isOwnerCurrent() || !isCurrent()) return false;
    return ProfileLocalWrites.run(() async {
      await write(id);
      return isOwnerCurrent() && isCurrent();
    });
  }
}
