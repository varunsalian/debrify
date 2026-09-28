import '../../../models/iptv_cw_entry.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';

/// Removes one movie or every episode represented by a collapsed series card.
/// The existing store owns the transaction, sync records and database drain.
class HomeIptvHistoryRemoval {
  const HomeIptvHistoryRemoval(this.owner);
  final ProfileSessionOwner owner;

  Future<bool> remove(
    IptvCwEntry entry, {
    required bool Function() isCurrent,
  }) async {
    bool current() =>
        isCurrent() && owner == ProfileSessionMemory.captureOwner();
    if (!current()) return false;
    final Future<void> Function() write;
    if (entry.isSeries) {
      final seriesId = (entry.raw['seriesId'] as String?) ?? '';
      if (seriesId.isEmpty) return false;
      final playlistId = (entry.raw['playlistId'] as String?) ?? '';
      write = () => StorageService.removeIptvContinueWatchingSeries(
        playlistId: playlistId,
        seriesId: seriesId,
      );
    } else {
      final url = (entry.raw['url'] as String?) ?? entry.routeKey;
      if (url.isEmpty) return false;
      write = () => StorageService.removeIptvContinueWatchingItem(url);
    }
    final scope = owner.scope;
    if (scope == null) {
      await write();
    } else {
      await ProfileRuntime.withCapturedScope(scope, write);
    }
    return current();
  }
}
