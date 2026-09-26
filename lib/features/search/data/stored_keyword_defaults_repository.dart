import '../../../models/torrent_filter_state.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';
import 'keyword_defaults_repository.dart';

/// Reads the existing five preference lists without changing their keys,
/// serialization, read order or enum-name matching rules.
class StoredKeywordDefaultsRepository implements KeywordDefaultsRepository {
  const StoredKeywordDefaultsRepository({required this.owner});
  final ProfileSessionOwner owner;

  @override
  bool get isCurrent => owner == ProfileSessionMemory.captureOwner();

  @override
  Future<TorrentFilterState> load() async {
    if (!isCurrent) return const TorrentFilterState.empty();
    Future<TorrentFilterState> read() async {
      final qualities = await StorageService.getDefaultFilterQualities();
      final sources = await StorageService.getDefaultFilterRipSources();
      final languages = await StorageService.getDefaultFilterLanguages();
      final sizes = await StorageService.getDefaultFilterSizes();
      final ranges = await StorageService.getDefaultFilterDynamicRanges();
      if (!isCurrent) return const TorrentFilterState.empty();
      return TorrentFilterState(
        qualities: _parse(qualities, QualityTier.values),
        ripSources: _parse(sources, RipSourceCategory.values),
        languages: _parse(languages, AudioLanguage.values),
        sizes: _parse(sizes, SizeBucket.values),
        dynamicRanges: _parse(ranges, DynamicRange.values),
      );
    }

    final scope = owner.scope;
    return scope == null
        ? read()
        : ProfileRuntime.withCapturedScope(scope, read);
  }

  Set<T> _parse<T extends Enum>(List<String> names, List<T> values) => {
    for (final name in names)
      for (final value in values)
        if (value.name == name) value,
  };
}
