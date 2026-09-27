import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/storage_service.dart';
import '../data/home_continuation_layout_repository.dart';

final homeContinuationLayoutRepositoryProvider =
    Provider<HomeContinuationLayoutRepository>(
      (ref) => HomeContinuationLayoutRepository(
        readMerged: StorageService.getHomeCwMergedRows,
      ),
      dependencies: const [],
    );
