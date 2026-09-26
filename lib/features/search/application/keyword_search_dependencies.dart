import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/engine_keyword_search_repository.dart';
import '../data/keyword_search_repository.dart';
import '../models/search_session.dart';

final keywordSearchRepositoryProvider = Provider.autoDispose
    .family<KeywordSearchRepository, SearchSession>(
      (ref, session) => EngineKeywordSearchRepository(owner: session.owner),
      retry: (count, error) => null,
    );
