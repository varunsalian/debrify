import '../../../models/stremio_addon.dart';
import '../../../services/mdblist/mdblist_models.dart' show MdblistTitleStatus;
import '../../../services/simkl/simkl_service.dart' show SimklTitleStatus;
import '../../../services/trakt/trakt_service.dart' show TraktTitleStatus;

typedef HomeDetailRead<T> =
    Future<T> Function(String id, String type, bool Function() isCurrent);

/// Lazy detail reads. Services own shared caches; each route owns acceptance.
class HomeDetailReaders {
  const HomeDetailReaders({
    required this.isOwnerCurrent,
    required HomeDetailRead<TraktTitleStatus?> trakt,
    required HomeDetailRead<SimklTitleStatus?> simkl,
    required HomeDetailRead<MdblistTitleStatus?> mdblist,
    required HomeDetailRead<List<StremioMeta>> recommendations,
    required HomeDetailRead<StremioMeta?> metadata,
  }) : _trakt = trakt,
       _simkl = simkl,
       _mdblist = mdblist,
       _recommendations = recommendations,
       _metadata = metadata;

  final bool Function() isOwnerCurrent;
  final HomeDetailRead<TraktTitleStatus?> _trakt;
  final HomeDetailRead<SimklTitleStatus?> _simkl;
  final HomeDetailRead<MdblistTitleStatus?> _mdblist;
  final HomeDetailRead<List<StremioMeta>> _recommendations;
  final HomeDetailRead<StremioMeta?> _metadata;

  Future<T?> _read<T>(
    HomeDetailRead<T?> read,
    String id,
    String type,
    bool Function() isCurrent,
  ) async {
    bool current() => isOwnerCurrent() && isCurrent();
    if (!current()) return null;
    // Preserve service errors; retirement is not a new retry/error policy.
    final result = await read(id, type, current);
    return current() ? result : null;
  }

  Future<TraktTitleStatus?> trakt(
    String id,
    String type, {
    required bool Function() isCurrent,
  }) => _read(_trakt, id, type, isCurrent);

  Future<SimklTitleStatus?> simkl(
    String id,
    String type, {
    required bool Function() isCurrent,
  }) => _read(_simkl, id, type, isCurrent);

  Future<MdblistTitleStatus?> mdblist(
    String id,
    String type, {
    required bool Function() isCurrent,
  }) => _read(_mdblist, id, type, isCurrent);

  Future<List<StremioMeta>> recommendations(
    String id,
    String type, {
    required bool Function() isCurrent,
  }) async => await _read(_recommendations, id, type, isCurrent) ?? const [];

  Future<StremioMeta?> metadata(
    String id,
    String type, {
    required bool Function() isCurrent,
  }) => _read(_metadata, id, type, isCurrent);
}
