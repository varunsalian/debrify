import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/engine/settings_manager.dart';
import '../../../services/torrent_service.dart';
import '../data/engine_keyword_sources_repository.dart';
import '../data/keyword_sources_repository.dart';
import '../models/search_session.dart';

final keywordSourcesRepositoryProvider = Provider.autoDispose
    .family<KeywordSourcesRepository, SearchSession>(
      (ref, session) => EngineKeywordSourcesRepository(
        owner: session.owner,
        settings: SettingsManager(),
        engines: TorrentService.getKeywordSearchEngines,
      ),
      retry: (count, error) => null,
    );
