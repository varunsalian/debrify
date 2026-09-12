import 'package:flutter/material.dart';

import '../models/stremio_addon.dart';
import '../services/collection_native_source_service.dart';
import '../services/profiles/profile_runtime.dart';

final _activeTitleNotices =
    Expando<ScaffoldFeatureController<SnackBar, SnackBarClosedReason>>();

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
  final messenger = ScaffoldMessenger.maybeOf(context);
  // A newer selection replaces the loading notice immediately. Queuing these
  // notices would let a fast lookup try to close a snackbar that is not first.
  messenger?.clearSnackBars();
  messenger?.removeCurrentSnackBar();
  final notice = messenger?.showSnackBar(
    const SnackBar(
      content: Text('Loading title…'),
      duration: Duration(seconds: 4),
    ),
  );
  if (messenger != null && notice != null) {
    _activeTitleNotices[messenger] = notice;
    notice.closed.then((_) {
      if (identical(_activeTitleNotices[messenger], notice)) {
        _activeTitleNotices[messenger] = null;
      }
    });
  }
  var selected = item;
  try {
    selected =
        await (resolve ??
                CollectionNativeSourceService.instance.resolveIdentity)(item)
            .timeout(const Duration(seconds: 4), onTimeout: () => item);
  } catch (_) {
    // Native IDs remain usable by capable addons when enrichment is unavailable.
  } finally {
    if (context.mounted &&
        messenger != null &&
        notice != null &&
        identical(_activeTitleNotices[messenger], notice)) {
      notice.close();
    }
  }
  if (context.mounted &&
      scope == ProfileRuntime.scope.value &&
      (route == null || route.isCurrent)) {
    onOpen(selected);
  }
}
