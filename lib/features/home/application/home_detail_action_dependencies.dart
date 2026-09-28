import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profile_tracker_title_actions.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/tracker_title_actions.dart';

/// One stateless dependency per originating profile; routes supply their guard.
final homeDetailActionsProvider = Provider.autoDispose
    .family<TrackerTitleActions, ProfileSessionOwner>(
      (ref, owner) => ProfileTrackerTitleActions(owner),
      retry: (count, error) => null,
      dependencies: const [],
    );
