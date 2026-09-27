import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_source_editing_repository.dart';

final homeSourceEditingRepositoryProvider = Provider.autoDispose
    .family<HomeSourceEditingRepository, ProfileSessionOwner>(
      (ref, owner) => HomeSourceEditingRepository(owner),
      dependencies: const [],
    );
