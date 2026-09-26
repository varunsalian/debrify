import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/stremio_service.dart';
import '../data/catalog_search_repository.dart';
import '../data/stremio_catalog_search_repository.dart';
import '../models/search_session.dart';

final catalogSearchRepositoryProvider = Provider.autoDispose
    .family<CatalogSearchRepository, SearchSession>(
      (ref, session) => StremioCatalogSearchRepository(
        owner: session.owner,
        service: StremioService.instance,
      ),
      retry: (count, error) => null,
    );
