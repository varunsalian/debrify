import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/simkl/simkl_continue_watching_service.dart';
import '../data/home_simkl_continuation_reader.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/simkl/simkl_continue_watching_removal.dart';

final homeSimklContinuationReaderProvider =
    Provider<HomeSimklContinuationReader>(
      (ref) =>
          () => SimklContinueWatchingService.instance.fetchItems(),
      dependencies: const [],
    );

final homeSimklHistoryRemovalProvider = Provider.autoDispose
    .family<SimklContinueWatchingRemoval, ProfileSessionOwner>(
      (ref, owner) => SimklContinueWatchingRemoval(owner),
      dependencies: const [],
    );
