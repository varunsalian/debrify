import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/simkl/simkl_continue_watching_service.dart';
import '../data/home_simkl_continuation_reader.dart';

final homeSimklContinuationReaderProvider =
    Provider<HomeSimklContinuationReader>(
      (ref) =>
          () => SimklContinueWatchingService.instance.fetchItems(),
      dependencies: const [],
    );
