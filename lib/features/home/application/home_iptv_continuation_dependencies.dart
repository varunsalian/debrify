import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/iptv_cw_history.dart';
import '../../../services/storage_service.dart';

final homeIptvContinuationRepositoryProvider = Provider<IptvCwHistory>(
  (ref) => IptvCwHistory(readHistory: StorageService.getIptvContinueWatching),
  dependencies: const [],
);
