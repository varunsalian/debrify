import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/search_session.dart';

/// Dialogs can outlive the originating route's profile handoff notification.
/// Clear their private state on that handoff without starting another action.
final searchSessionActiveProvider = Provider.autoDispose
    .family<bool, SearchSession>((ref, session) {
      void changed() => ref.invalidateSelf();
      ProfileRuntime.scope.addListener(changed);
      ref.onDispose(() => ProfileRuntime.scope.removeListener(changed));
      return session.owner == ProfileSessionMemory.captureOwner();
    }, retry: (count, error) => null);
