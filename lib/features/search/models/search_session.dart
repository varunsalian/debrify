import '../../../services/profiles/profile_session_memory.dart';

/// Mutable search state belongs to one screen in one profile session. Separate
/// routes must not share it just because they happen to have the same query.
class SearchSession {
  final ProfileSessionOwner owner;
  final Object viewIdentity;

  const SearchSession({required this.owner, required this.viewIdentity});

  @override
  bool operator ==(Object other) =>
      other is SearchSession &&
      other.owner == owner &&
      identical(other.viewIdentity, viewIdentity);

  @override
  int get hashCode => Object.hash(owner, identityHashCode(viewIdentity));
}
