import 'package:flutter/material.dart';

import '../models/stremio_addon.dart';
import '../services/collection_native_source_service.dart';
import '../services/profiles/profile_runtime.dart';

/// Resolve only a selected native title. Browsing a recommendation rail never
/// waits for external IDs, and the host retains its existing navigation action.
Future<void> openMetadataTitle(
  BuildContext context,
  StremioMeta item,
  ValueChanged<StremioMeta> onOpen, {
  Future<StremioMeta> Function(StremioMeta)? resolve,
}) async {
  if (!item.id.startsWith('tmdb:') || item.effectiveImdbId != null) {
    onOpen(item);
    return;
  }
  final scope = ProfileRuntime.scope.value;
  final route = ModalRoute.of(context);
  final notice = ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(
      content: Text('Loading title…'),
      duration: Duration(seconds: 4),
    ),
  );
  var selected = item;
  try {
    selected =
        await (resolve ??
                CollectionNativeSourceService.instance.resolveIdentity)(item)
            .timeout(const Duration(seconds: 4), onTimeout: () => item);
  } catch (_) {
    // Native IDs remain usable by capable addons when enrichment is unavailable.
  } finally {
    if (context.mounted) notice?.close();
  }
  if (context.mounted &&
      scope == ProfileRuntime.scope.value &&
      (route == null || route.isCurrent)) {
    onOpen(selected);
  }
}
