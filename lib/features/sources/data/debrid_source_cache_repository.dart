import '../../../services/premiumize_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';
import '../../../services/torbox_service.dart';
import 'source_cache_repository.dart';

typedef SourceTorboxCacheCheck =
    Future<Set<String>> Function({
      required String apiKey,
      required List<String> infoHashes,
    });
typedef SourcePremiumizeCacheCheck =
    Future<List<bool>> Function(String key, List<String> hashes);

class DebridSourceCacheRepository implements SourceCacheRepository {
  final ProfileSessionOwner owner;
  final SourceTorboxCacheCheck torboxCheck;
  final SourcePremiumizeCacheCheck premiumizeCheck;

  const DebridSourceCacheRepository({
    required this.owner,
    this.torboxCheck = TorboxService.checkCachedTorrents,
    this.premiumizeCheck = PremiumizeService.checkCache,
  });

  @override
  bool get isCurrent => owner == ProfileSessionMemory.captureOwner();

  @override
  Future<SourceCacheSession> open() async {
    if (!isCurrent) throw StateError('Retired source cache session');
    Future<List<Object?>> read() => Future.wait([
      StorageService.getTorboxCacheCheckEnabled(),
      StorageService.getTorboxIntegrationEnabled(),
      StorageService.getTorboxApiKey(),
      StorageService.getPremiumizeCacheCheckEnabled(),
      StorageService.getPremiumizeIntegrationEnabled(),
      StorageService.getPremiumizeApiKey(),
    ]);
    final scope = owner.scope;
    final values = await (scope == null
        ? read()
        : ProfileRuntime.withCapturedScope(scope, read));
    final tb = values[2] as String?;
    final pm = values[5] as String?;
    return _DebridSourceCacheSession(
      repository: this,
      torboxKey: tb,
      premiumizeKey: pm,
      torboxEnabled:
          values[0] as bool && values[1] as bool && (tb?.isNotEmpty ?? false),
      premiumizeEnabled:
          values[3] as bool && values[4] as bool && (pm?.isNotEmpty ?? false),
    );
  }
}

class _DebridSourceCacheSession implements SourceCacheSession {
  final DebridSourceCacheRepository repository;
  final String? torboxKey;
  final String? premiumizeKey;
  @override
  final bool torboxEnabled;
  @override
  final bool premiumizeEnabled;

  const _DebridSourceCacheSession({
    required this.repository,
    required this.torboxKey,
    required this.premiumizeKey,
    required this.torboxEnabled,
    required this.premiumizeEnabled,
  });

  @override
  Future<Set<String>> torbox(List<String> hashes) {
    if (!repository.isCurrent) {
      throw StateError('Retired source cache session');
    }
    return repository.torboxCheck(apiKey: torboxKey!, infoHashes: hashes);
  }

  @override
  Future<List<bool>> premiumize(List<String> hashes) {
    if (!repository.isCurrent) {
      throw StateError('Retired source cache session');
    }
    return repository.premiumizeCheck(premiumizeKey!, hashes);
  }
}
