import '../../../services/profiles/profile_session_memory.dart';
import '../models/keyword_snapshot.dart';
import 'keyword_snapshot_repository.dart';

/// Adapters borrow ONE process-lifetime store. Creating/discarding a provider or
/// screen must not register another store with the profile lifecycle registry.
class MemoryKeywordSnapshotRepository implements KeywordSnapshotRepository {
  const MemoryKeywordSnapshotRepository({required this.owner});
  final ProfileSessionOwner owner;
  static final ProfileSessionMemory<KeywordSnapshot> _preserved =
      ProfileSessionMemory<KeywordSnapshot>();

  bool get _current => owner == ProfileSessionMemory.captureOwner();

  @override
  KeywordSnapshot? take(String variant, {required bool allowed}) {
    if (!_current) return null;
    final snapshot = _preserved.take(
      owner,
      where: (value) => value.variant == variant && value.query.isNotEmpty,
    );
    // A denied matching snapshot is still consumed, as in the legacy screen.
    return allowed ? snapshot : null;
  }

  @override
  void store(KeywordSnapshot snapshot) {
    // An outgoing view must neither publish private data nor overwrite a newer
    // incoming snapshot when its disposal runs late in the handoff.
    if (_current) _preserved.store(owner, snapshot);
  }
}
