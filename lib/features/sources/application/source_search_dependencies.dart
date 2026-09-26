import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/source_search_repository.dart';
import '../data/service_source_search_repository.dart';
import '../models/sources_session.dart';

final sourceSearchRepositoryProvider = Provider.autoDispose
    .family<SourceSearchRepository, SourcesSession>(
      (ref, session) => ServiceSourceSearchRepository(owner: session.owner),
      retry: (count, error) => null,
      dependencies: const [],
    );
