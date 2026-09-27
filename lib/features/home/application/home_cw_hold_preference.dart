import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';

/// Fresh read per gesture; no application state or competing preference cache.
final homeCwHoldPreferenceProvider = Provider.autoDispose
    .family<Future<bool> Function(), ProfileSessionOwner>((ref, owner) {
      return () {
        final scope = owner.scope;
        return scope == null
            ? StorageService.getHomeCwHoldToQuickPlay()
            : ProfileRuntime.withCapturedScope(
                scope,
                StorageService.getHomeCwHoldToQuickPlay,
              );
      };
    }, dependencies: const []);
