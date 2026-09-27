import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/stremio_service.dart';
import '../../../services/storage_service.dart';
import '../data/discover_source_repository.dart';
import '../models/discover_source_state.dart';

final discoverSourceRepositoryProvider = Provider.autoDispose
    .family<DiscoverSourceRepository, DiscoverSourceSession>(
      (ref, session) {
        bool current() => session.owner == ProfileSessionMemory.captureOwner();
        Future<T> scoped<T>(Future<T> Function() read) {
          if (!current()) throw StateError('Discover source owner retired');
          final scope = session.owner.scope;
          return scope == null
              ? read()
              : ProfileRuntime.withCapturedScope(scope, read);
        }

        return DiscoverSourceRepository(
          readDefault: () => scoped(() async {
            final value = await StorageService.getDiscoverDefaultSource();
            return value == StorageService.discoverDefaultRememberLast
                ? null
                : value;
          }),
          readLast: () => scoped(StorageService.getDiscoverLastSource),
          readAddons: () => scoped(StremioService.instance.getCatalogAddons),
          writeLast: (source, isCurrent) =>
              StorageService.setDiscoverLastSource(
                source,
                canContinue: () => current() && isCurrent(),
              ),
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
