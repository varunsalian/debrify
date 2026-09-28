import '../../../services/alldebrid_service.dart';
import '../../../services/debrid_service.dart';
import '../../../services/pikpak_api_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';

/// Existing provider rejection cleanup may finish after its action retires.
/// It must retain the original endpoint and credentials, never the incoming scope.
Future<void> cleanupRejectedSource(
  Object error, {
  ProfileSessionOwner? owner,
  Future<void> Function(String, String)? deleteRealDebrid,
  Future<void> Function(String, String)? deleteAllDebrid,
}) => _inOwner(owner, () async {
  try {
    if (error is TorrentNotCachedException) {
      await (deleteRealDebrid ?? DebridService.deleteTorrent)(
        error.apiKey,
        error.torrentId,
      );
    } else if (error is AllDebridTorrentNotReadyException) {
      await (deleteAllDebrid ?? AllDebridService.deleteMagnet)(
        error.apiKey,
        error.magnetId,
      );
    }
  } catch (_) {}
});

/// Only fresh RD/PikPak acquisitions are removed for an episode mismatch.
/// Other providers may reuse shared account entries and must remain untouched.
Future<void> cleanupWrongEpisode(
  String provider, {
  required ProfileSessionOwner owner,
  String? rdTorrentId,
  String? pikpakFileId,
}) => _inOwner(owner, () async {
  try {
    if (provider == 'debrid' && (rdTorrentId?.isNotEmpty ?? false)) {
      final key = (await StorageService.getApiKey()) ?? '';
      await DebridService.deleteTorrent(key, rdTorrentId!);
    } else if (provider == 'pikpak' && (pikpakFileId?.isNotEmpty ?? false)) {
      await PikPakApiService.instance.batchDeleteFiles([pikpakFileId!]);
    }
  } catch (_) {}
});

Future<void> _inOwner(
  ProfileSessionOwner? owner,
  Future<void> Function() action,
) {
  if (owner == null) return action();
  final scope = owner.scope;
  return scope == null
      ? ProfileRuntime.withoutCapturedScope(action)
      : ProfileRuntime.withCapturedScope(scope, action);
}
