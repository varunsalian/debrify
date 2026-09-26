import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/source_seasons_repository.dart';
import '../data/stremio_source_seasons_repository.dart';
import '../models/sources_session.dart';

final sourceSeasonsRepositoryProvider = Provider.autoDispose
    .family<SourceSeasonsRepository, SourcesSession>(
      (ref, session) => StremioSourceSeasonsRepository(session),
      retry: (count, error) => null,
      dependencies: const [],
    );

final sourcesSessionActiveProvider = Provider.autoDispose
    .family<bool, SourcesSession>(
      (ref, session) {
        void changed() => ref.invalidateSelf();
        ProfileRuntime.scope.addListener(changed);
        ref.onDispose(() => ProfileRuntime.scope.removeListener(changed));
        return session.owner == ProfileSessionMemory.captureOwner();
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
