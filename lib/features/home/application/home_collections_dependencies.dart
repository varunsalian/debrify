import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/home_collections_store.dart';
import '../data/home_collections_repository.dart';

final homeCollectionsRepositoryProvider = Provider<HomeCollectionsRepository>(
  (ref) => HomeCollectionsRepository(
    read: HomeCollectionsStore.instance.getCollections,
    signature: HomeCollectionsStore.signatureOfAsync,
    onReadFailure: () =>
        debugPrint('Home: saved collections could not be loaded'),
  ),
  dependencies: const [],
);
