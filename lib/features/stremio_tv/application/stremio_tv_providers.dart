import 'package:debrify/services/storage/stremio_catalog_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
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
          read: () => scoped(StremioCatalogStorage.getStremioTvLocalCatalogs),
          add: (catalog, current) => scoped(
            () => StremioCatalogStorage.addStremioTvLocalCatalog(
              catalog,
              canContinue: current,
            ),
          ),
          update: (catalog, current) => scoped(
            () => StremioCatalogStorage.updateStremioTvLocalCatalog(
              catalog,
              canContinue: current,
            ),
          ),
        );
      },
    );
