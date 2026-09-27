import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';
import '../data/home_pikpak_only_repository.dart';
import '../models/home_catalog_session.dart';

final homePikpakOnlyRepositoryProvider = Provider.autoDispose
    .family<HomePikpakOnlyRepository, HomeCatalogSession>(
      (ref, session) {
        bool Function() guarded(bool Function() current) =>
            () =>
                session.owner == ProfileSessionMemory.captureOwner() &&
                current();
        return HomePikpakOnlyRepository(
          readPikpakEnabled: (current) =>
              StorageService.getPikPakEnabled(canContinue: guarded(current)),
          readRealDebrid: (current) =>
              StorageService.getApiKey(canContinue: guarded(current)),
          readTorbox: (current) =>
              StorageService.getTorboxApiKey(canContinue: guarded(current)),
          readPremiumize: (current) =>
              StorageService.getPremiumizeApiKey(canContinue: guarded(current)),
          readAllDebrid: (current) =>
              StorageService.getAllDebridApiKey(canContinue: guarded(current)),
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
