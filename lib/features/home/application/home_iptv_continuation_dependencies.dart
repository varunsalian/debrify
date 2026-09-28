import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/iptv_cw_history.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_iptv_history_removal.dart';
import '../../../services/storage_service.dart';

final homeIptvContinuationRepositoryProvider = Provider<IptvCwHistory>(
  (ref) => IptvCwHistory(readHistory: StorageService.getIptvContinueWatching),
  dependencies: const [],
);

final homeIptvHistoryRemovalProvider = Provider.autoDispose
    .family<HomeIptvHistoryRemoval, ProfileSessionOwner>(
      (ref, owner) => HomeIptvHistoryRemoval(owner),
      dependencies: const [],
    );
