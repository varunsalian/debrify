import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/pikpak_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import '../../../services/premiumize_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/torbox_service.dart';
import 'keyword_cache_repository.dart';

typedef TorboxCacheCheck =
    Future<Set<String>> Function({
      required String apiKey,
      required List<String> infoHashes,
    });
typedef PremiumizeCacheCheck =
    Future<List<bool>> Function(String key, List<String> hashes);

class DebridKeywordCacheRepository implements KeywordCacheRepository {
  final ProfileSessionOwner owner;
  final TorboxCacheCheck torboxCheck;
  final PremiumizeCacheCheck premiumizeCheck;

  const DebridKeywordCacheRepository({
    required this.owner,
    this.torboxCheck = TorboxService.checkCachedTorrents,
    this.premiumizeCheck = PremiumizeService.checkCache,
  });

  @override
  bool get isCurrent => owner == ProfileSessionMemory.captureOwner();

  @override
  Future<KeywordCacheSession> open() async {
    if (!isCurrent) throw StateError('Retired keyword cache session');
    Future<List<Object?>> read() => Future.wait([
      TorboxStorage.getTorboxCacheCheckEnabled(),
      TorboxStorage.getTorboxIntegrationEnabled(),
      TorboxStorage.getTorboxApiKey(),
      PremiumizeStorage.getPremiumizeCacheCheckEnabled(),
      PremiumizeStorage.getPremiumizeIntegrationEnabled(),
      PremiumizeStorage.getPremiumizeApiKey(),
      RealDebridStorage.getApiKey(),
      RealDebridStorage.getRealDebridIntegrationEnabled(),
      AllDebridStorage.getAllDebridApiKey(),
      AllDebridStorage.getAllDebridIntegrationEnabled(),
      PikpakStorage.getPikPakEnabled(),
    ]);
    final scope = owner.scope;
    final values = await (scope == null
        ? read()
        : ProfileRuntime.withCapturedScope(scope, read));
    final tb = values[2] as String?;
    final pm = values[5] as String?;
    final rd = values[6] as String?;
    final ad = values[8] as String?;
    return _DebridKeywordCacheSession(
      repository: this,
      torboxKey: tb,
      premiumizeKey: pm,
      torboxEnabled:
          values[0] as bool && values[1] as bool && (tb?.isNotEmpty ?? false),
      premiumizeEnabled:
          values[3] as bool && values[4] as bool && (pm?.isNotEmpty ?? false),
      otherProviderActive:
          (values[7] as bool && (rd?.isNotEmpty ?? false)) ||
          (values[4] as bool && (pm?.isNotEmpty ?? false)) ||
          (values[9] as bool && (ad?.isNotEmpty ?? false)) ||
          values[10] as bool,
    );
  }
}

class _DebridKeywordCacheSession implements KeywordCacheSession {
  final DebridKeywordCacheRepository repository;
  final String? torboxKey;
  final String? premiumizeKey;
  @override
  final bool torboxEnabled;
  @override
  final bool premiumizeEnabled;
  @override
  final bool otherProviderActive;

  const _DebridKeywordCacheSession({
    required this.repository,
    required this.torboxKey,
    required this.premiumizeKey,
    required this.torboxEnabled,
    required this.premiumizeEnabled,
    required this.otherProviderActive,
  });

  @override
  Future<Set<String>> torbox(List<String> hashes) {
    if (!repository.isCurrent) {
      throw StateError('Retired keyword cache session');
    }
    return repository.torboxCheck(apiKey: torboxKey!, infoHashes: hashes);
  }

  @override
  Future<List<bool>> premiumize(List<String> hashes) {
    if (!repository.isCurrent) {
      throw StateError('Retired keyword cache session');
    }
    return repository.premiumizeCheck(premiumizeKey!, hashes);
  }
}
