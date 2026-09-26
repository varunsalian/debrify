import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/keyword_defaults_repository.dart';
import '../data/stored_keyword_defaults_repository.dart';
import '../models/search_session.dart';

final keywordDefaultsRepositoryProvider = Provider.autoDispose
    .family<KeywordDefaultsRepository, SearchSession>(
      (ref, session) => StoredKeywordDefaultsRepository(owner: session.owner),
      retry: (count, error) => null,
    );
