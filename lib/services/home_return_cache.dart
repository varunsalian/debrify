import 'profiles/profile_session_memory.dart';

/// Data only: Home can unmount its players, timers and focus nodes while a
/// completed board remains available for a short same-session return.
class HomeReturnCache<T> {
  static int _revision = 0;
  static int get revision => _revision;

  /// Also retires snapshots being prepared by an outgoing screen.
  static void invalidate() => _revision++;

  final _memory =
      ProfileSessionMemory<({T value, int revision, DateTime loadedAt})>();

  void store(
    ProfileSessionOwner owner,
    T value, {
    required int revision,
    required DateTime loadedAt,
  }) {
    if (revision != _revision || owner != ProfileSessionMemory.captureOwner()) {
      return;
    }
    _memory.store(owner, (
      value: value,
      revision: revision,
      loadedAt: loadedAt,
    ));
  }

  T? take(ProfileSessionOwner owner, {DateTime? now}) {
    final entry = _memory.take(owner);
    if (entry == null ||
        entry.revision != _revision ||
        (now ?? DateTime.now()).difference(entry.loadedAt) >=
            const Duration(minutes: 5)) {
      return null;
    }
    return entry.value;
  }
}
