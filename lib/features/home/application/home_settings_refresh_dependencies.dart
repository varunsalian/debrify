import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/home_collections_store.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/home_catalog_session.dart';
import 'home_settings_refresh.dart';

final homeSettingsRefreshProvider = Provider.autoDispose
    .family<HomeSettingsRefresh, HomeCatalogSession>(
      (ref, session) {
        final collectionSession = HomeCollectionsStore.captureSession();
        final operation = HomeSettingsRefresh(
          isOwnerCurrent: () =>
              session.owner == ProfileSessionMemory.captureOwner() &&
              collectionSession == HomeCollectionsStore.captureSession(),
        );
        ref.onDispose(operation.dispose);
        return operation;
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
