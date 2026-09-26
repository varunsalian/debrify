import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/source_settings_repository.dart';
import '../data/stored_source_settings_repository.dart';
import '../models/sources_session.dart';

final sourceSettingsRepositoryProvider = Provider.autoDispose
    .family<SourceSettingsRepository, SourcesSession>(
      (ref, session) => StoredSourceSettingsRepository(session),
      retry: (count, error) => null,
      dependencies: const [],
    );
