import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/series_source_service.dart';
import '../data/home_bound_counts_repository.dart';
import '../models/home_catalog_session.dart';

final homeBoundCountsRepositoryProvider = Provider.autoDispose
    .family<HomeBoundCountsRepository, HomeCatalogSession>(
      (ref, session) => HomeBoundCountsRepository(
        readCount: (id, current) async {
          bool active() =>
              session.owner == ProfileSessionMemory.captureOwner() && current();
          Future<int> read() async => (await SeriesSourceService.getSources(
            id,
            canContinue: active,
          )).length;
          final scope = session.owner.scope;
          return scope == null
              ? read()
              : ProfileRuntime.withCapturedScope(scope, read);
        },
      ),
      retry: (count, error) => null,
      dependencies: const [],
    );
