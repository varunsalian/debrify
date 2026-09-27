import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';
import '../../../services/local_history_removal.dart';

final homeLocalHistoryRemovalProvider = Provider.autoDispose
    .family<LocalHistoryRemoval, ProfileSessionOwner>((ref, owner) {
      return LocalHistoryRemoval(
        isOwnerCurrent: () => owner == ProfileSessionMemory.captureOwner(),
        write: (id) {
          final scope = owner.scope;
          Future<void> remove() async {
            await StorageService.removeContinueWatchingItem(id);
            await StorageService.clearPlaybackStateByImdbId(id);
          }

          return scope == null
              ? remove()
              : ProfileRuntime.withCapturedScope(scope, remove);
        },
      );
    }, dependencies: const []);
