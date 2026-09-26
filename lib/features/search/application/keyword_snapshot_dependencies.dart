import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_session_memory.dart';
import '../data/keyword_snapshot_repository.dart';
import '../data/memory_keyword_snapshot_repository.dart';

/// Snapshot consumption precedes SearchSession bootstrap. This dependency is
/// keyed by its captured owner; variant matching stays explicit on each take.
/// The screen retains the plain adapter for disposal, without a WidgetRef read.
final keywordSnapshotRepositoryProvider = Provider.autoDispose
    .family<KeywordSnapshotRepository, ProfileSessionOwner>(
      (ref, owner) => MemoryKeywordSnapshotRepository(owner: owner),
      retry: (count, error) => null,
    );
