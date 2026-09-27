import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/native_series_metadata_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/stremio_service.dart';
import '../data/home_catalog_origin_repository.dart';

final homeCatalogOriginRepositoryProvider = Provider.autoDispose
    .family<HomeCatalogOriginRepository, ProfileSessionOwner>(
      (ref, owner) {
        bool current() => owner == ProfileSessionMemory.captureOwner();
        Future<T> scoped<T>(Future<T> Function() action) {
          final scope = owner.scope;
          return scope == null
              ? action()
              : ProfileRuntime.withCapturedScope(scope, action);
        }

        return HomeCatalogOriginRepository(
          nativeAddon: NativeSeriesMetadataService.addon,
          isOwnerCurrent: current,
          scopeProgress: (item, addon, canContinue) => scoped(
            () => StremioService.instance.scopeSeriesProgress(
              item,
              addon,
              canContinue: () => current() && canContinue(),
            ),
          ),
          readCustomOrigin: (id) =>
              scoped(() => StremioService.instance.addonForCustomProgress(id)),
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
