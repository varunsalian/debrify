import '../../../services/profiles/profile_session_memory.dart';

/// Local continuation state belongs to one view in one profile epoch.
class HomeContinuationSession {
  const HomeContinuationSession({
    required this.owner,
    required this.viewIdentity,
  });

  final ProfileSessionOwner owner;
  final Object viewIdentity;

  @override
  bool operator ==(Object other) =>
      other is HomeContinuationSession &&
      other.owner == owner &&
      identical(other.viewIdentity, viewIdentity);

  @override
  int get hashCode => Object.hash(owner, identityHashCode(viewIdentity));
}
