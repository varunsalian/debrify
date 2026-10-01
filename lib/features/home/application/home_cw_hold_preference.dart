import 'package:debrify/services/storage/home_page_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';

/// Fresh read per gesture; no application state or competing preference cache.
final homeCwHoldPreferenceProvider = Provider.autoDispose
    .family<Future<bool> Function(), ProfileSessionOwner>((ref, owner) {
      return () {
        final scope = owner.scope;
        return scope == null
            ? HomePageStorage.getHomeCwHoldToQuickPlay()
            : ProfileRuntime.withCapturedScope(
                scope,
                HomePageStorage.getHomeCwHoldToQuickPlay,
              );
      };
    }, dependencies: const []);
