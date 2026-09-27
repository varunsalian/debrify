import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/stremio_addon.dart';
import '../../../services/storage_service.dart';

/// The existing storage API already supplies a typed, ordered list.
final homeWatchlistReaderProvider =
    Provider<Future<List<StremioMeta>> Function()>(
      (ref) => StorageService.getMyWatchlistItems,
      dependencies: const [],
    );
