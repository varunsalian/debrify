import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/profiles/profile_policy.dart';
import '../../../services/profiles/profile_policy_guard.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';
import '../models/home_catalog_session.dart';
import 'home_default_view.dart';

final homeDefaultViewReaderProvider = Provider<Future<String?> Function()>(
  (ref) => StorageService.getHomeDefaultSourceType,
  dependencies: const [],
);

/// Shares the mounted Home/catalog view identity, not its inventory or state.
final homeDefaultViewProvider = Provider.autoDispose
    .family<HomeDefaultView, HomeCatalogSession>(
      (ref, session) {
        final operation = HomeDefaultView(
          readSaved: ref.watch(homeDefaultViewReaderProvider),
          keywordAllowed: () =>
              ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch),
          isOwnerCurrent: () =>
              session.owner == ProfileSessionMemory.captureOwner(),
        );
        ref.onDispose(operation.dispose);
        return operation;
      },
      retry: (count, error) => null,
      dependencies: [homeDefaultViewReaderProvider],
    );
