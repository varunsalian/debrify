import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/profiles/profile_policy.dart';
import '../../../services/iptv_source_search.dart';
import '../../../services/media_server_service.dart';
import '../../../services/profiles/profile_policy_guard.dart';
import '../data/source_row_action_policy.dart';

final sourceRowActionPolicyProvider = Provider<SourceRowActionPolicy>(
  (ref) => SourceRowActionPolicy(
    isMediaServer: MediaServerService.owns,
    isIptv: IptvSourceSearch.owns,
    downloadsAllowed: () =>
        ProfilePolicyGuard.allowsSync(ProfileFeature.downloads),
  ),
  dependencies: const [],
);
