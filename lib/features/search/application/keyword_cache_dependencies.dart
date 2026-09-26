import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/debrid_keyword_cache_repository.dart';
import '../data/keyword_cache_repository.dart';
import '../models/search_session.dart';

final keywordCacheRepositoryProvider = Provider.autoDispose
    .family<KeywordCacheRepository, SearchSession>(
      (ref, session) => DebridKeywordCacheRepository(owner: session.owner),
      retry: (count, error) => null,
    );
