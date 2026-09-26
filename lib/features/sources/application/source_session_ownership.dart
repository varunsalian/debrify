import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_session_memory.dart';
import '../models/sources_session.dart';

/// Reads ownership at each call, including lifecycle clears without scope events.
/// The view captures this dependency while mounted so guards never need a Ref.
class SourceSessionOwnership {
  const SourceSessionOwnership(this.readOwner);

  final ProfileSessionOwner Function() readOwner;

  ProfileSessionOwner capture() => readOwner();
  bool isCurrent(SourcesSession session) => session.owner == readOwner();
}

final sourceSessionOwnershipProvider = Provider<SourceSessionOwnership>(
  (ref) => SourceSessionOwnership(ProfileSessionMemory.captureOwner),
);
