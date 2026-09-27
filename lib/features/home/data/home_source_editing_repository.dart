import '../../../models/series_source.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/series_source_service.dart' show SeriesSourceService;
import '../../../services/storage_service.dart';

typedef HomeSourceProviders = ({
  bool rd,
  bool torbox,
  bool premiumize,
  bool allDebrid,
  bool pikpak,
});

/// Home edits the complete title binding list, unlike the episode-filtered picker.
class HomeSourceEditingRepository {
  const HomeSourceEditingRepository(this.owner);
  final ProfileSessionOwner owner;

  Future<T?> _run<T>(
    Future<T?> Function(bool Function()) operation,
    bool Function() isCurrent,
  ) async {
    bool current() =>
        isCurrent() && owner == ProfileSessionMemory.captureOwner();
    if (!current()) return null;
    // Interactive source migration/writes must retain live-profile checks.
    return ProfileRuntime.withoutCapturedScope(() async {
      try {
        if (!current()) return null;
        final value = await operation(current);
        return current() ? value : null;
      } catch (_) {
        if (!current()) return null;
        rethrow;
      }
    });
  }

  Future<List<SeriesSource>?> load(
    String id, {
    required bool Function() isCurrent,
  }) => _run(
    (current) => SeriesSourceService.getSources(id, canContinue: current),
    isCurrent,
  );

  Future<bool> replace(
    String id,
    List<SeriesSource> sources, {
    required bool Function() isCurrent,
  }) async =>
      await _run((current) async {
        await SeriesSourceService.setSources(id, sources, canContinue: current);
        return true;
      }, isCurrent) ??
      false;

  Future<bool> remove(
    String id,
    SeriesSource source, {
    required bool Function() isCurrent,
  }) async =>
      await _run((current) async {
        await SeriesSourceService.removeSourceEntry(
          id,
          source,
          canContinue: current,
        );
        return true;
      }, isCurrent) ??
      false;

  Future<bool> save(
    String id,
    SeriesSource source, {
    required bool isMovie,
    required bool Function() isCurrent,
  }) async =>
      await _run((current) async {
        if (isMovie) {
          await SeriesSourceService.setSources(id, [
            source,
          ], canContinue: current);
        } else {
          await SeriesSourceService.addSource(id, source, canContinue: current);
        }
        return true;
      }, isCurrent) ??
      false;

  Future<HomeSourceProviders?> providers({
    required bool Function() isCurrent,
  }) => _run((current) async {
    final rd = await StorageService.getApiKey(canContinue: current);
    if (!current()) return null;
    final torbox = await StorageService.getTorboxApiKey(canContinue: current);
    if (!current()) return null;
    final premiumize = await StorageService.getPremiumizeApiKey(
      canContinue: current,
    );
    if (!current()) return null;
    final premiumizeEnabled =
        await StorageService.getPremiumizeIntegrationEnabled();
    if (!current()) return null;
    final allDebrid = await StorageService.getAllDebridApiKey(
      canContinue: current,
    );
    if (!current()) return null;
    final pikpak = await StorageService.getPikPakEnabled(canContinue: current);
    if (!current()) return null;
    return (
      rd: rd != null && rd.isNotEmpty,
      torbox: torbox != null && torbox.isNotEmpty,
      premiumize:
          premiumizeEnabled && premiumize != null && premiumize.isNotEmpty,
      allDebrid: allDebrid != null && allDebrid.isNotEmpty,
      pikpak: pikpak,
    );
  }, isCurrent);
}
