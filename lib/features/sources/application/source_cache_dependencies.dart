import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/source_cache_repository.dart';
import '../data/debrid_source_cache_repository.dart';
import '../models/sources_session.dart';

final sourceCacheRepositoryProvider = Provider.autoDispose
    .family<SourceCacheRepository, SourcesSession>(
      (ref, session) => DebridSourceCacheRepository(owner: session.owner),
      retry: (count, error) => null,
      dependencies: const [],
    );
