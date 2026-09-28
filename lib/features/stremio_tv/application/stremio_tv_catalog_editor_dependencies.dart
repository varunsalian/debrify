import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';
import '../data/stremio_tv_catalog_editor.dart';

/// Capture an owner synchronously when a picker opens, before its route builds.
/// Editors are stateless; simultaneous dialogs borrow no mutable operation state.
final stremioTvCatalogEditorFactoryProvider =
    Provider<StremioTvCatalogEditor Function()>(
      (ref) => () {
        final owner = ProfileSessionMemory.captureOwner();
        Future<T> scoped<T>(Future<T> Function() operation) {
          final scope = owner.scope;
          return scope == null
              ? operation()
              : ProfileRuntime.withCapturedScope(scope, operation);
        }

        return StremioTvCatalogEditor(
          isCurrent: () => owner == ProfileSessionMemory.captureOwner(),
          read: () => scoped(StorageService.getStremioTvLocalCatalogs),
          add: (catalog, current) => scoped(
            () => StorageService.addStremioTvLocalCatalog(
              catalog,
              canContinue: current,
            ),
          ),
          update: (catalog, current) => scoped(
            () => StorageService.updateStremioTvLocalCatalog(
              catalog,
              canContinue: current,
            ),
          ),
        );
      },
    );
