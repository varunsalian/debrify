import '../../../models/torrent.dart';
import '../../../services/alldebrid_service.dart';
import '../../../services/debrid_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/acquired_source.dart';
import 'pikpak_source_preparation.dart';
import 'source_acquisition.dart';
import 'source_magnet.dart';

/// Readiness and existing provider-specific rejection cleanup for manual pins.
class ManualSourcePreparation {
  const ManualSourcePreparation({this.acquisition = const SourceAcquisition()});

  final SourceAcquisition acquisition;

  /// Backend-only readiness probe for a manual pin. Cleanup of acquisitions
  /// that cannot be played stays with the provider implementation.
  Future<({bool ready, String? failureMessage})> prepare(
    String provider,
    Torrent torrent, {
    bool Function()? canContinue,
  }) {
    final owner = ProfileSessionMemory.captureOwner();
    bool current() =>
        owner == ProfileSessionMemory.captureOwner() &&
        (canContinue?.call() ?? true);
    Future<({bool ready, String? failureMessage})> run() =>
        _prepare(provider, torrent, canContinue: current);
    final scope = owner.scope;
    return scope == null
        ? ProfileRuntime.withoutCapturedScope(run)
        : ProfileRuntime.withCapturedScope(scope, run);
  }

  Future<({bool ready, String? failureMessage})> _prepare(
    String provider,
    Torrent torrent, {
    required bool Function() canContinue,
  }) async {
    if (!canContinue()) return (ready: false, failureMessage: null);
    AcquiredSource? res;
    String? failMessage;
    try {
      final magnet = await sourceMagnet(torrent);
      if (magnet != null && canContinue()) {
        final r = await acquisition.acquire(
          provider,
          magnet,
          torrent,
          canContinue: canContinue,
        );
        if (canContinue() && r.playUrl != null && r.playUrl!.isNotEmpty) {
          res = r;
        }
      }
    } on TorrentNotCachedException catch (e) {
      try {
        await DebridService.deleteTorrent(e.apiKey, e.torrentId);
      } catch (_) {}
    } on AllDebridTorrentNotReadyException catch (e) {
      try {
        await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
      } catch (_) {}
    } on PikPakSourceStillProcessing {
      // PikPak queued a download that isn't instantly playable — can't pin.
      failMessage =
          'Added to PikPak — it\'s still downloading. Pin it again once ready.';
    } on PikPakSourceFailed {
      failMessage = 'Download failed on PikPak.';
    } catch (_) {}
    return (ready: res != null, failureMessage: failMessage);
  }
}
