import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/mdblist/mdblist_list_source.dart';
import '../../../services/mdblist/mdblist_service.dart';
import '../data/lists_search_repository.dart';
import '../data/mdblist_search_repository.dart';
import '../models/search_session.dart';

final listsSearchRepositoryProvider = Provider.autoDispose
    .family<ListsSearchRepository, SearchSession>(
      (ref, session) => MdblistSearchRepository(
        owner: session.owner,
        service: MdblistService.instance,
        source: MdblistListSource.instance,
      ),
      retry: (count, error) => null,
    );
