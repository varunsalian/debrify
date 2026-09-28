import '../../../models/torrent.dart';
import '../../../services/alldebrid_service.dart';
import '../../../services/debrid_service.dart';
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
  }) async {
    AcquiredSource? res;
    String? failMessage;
    try {
      final magnet = await sourceMagnet(torrent);
      if (magnet != null && (canContinue?.call() ?? true)) {
        final r = await acquisition.acquire(
          provider,
          magnet,
          torrent,
          canContinue: canContinue,
        );
        if (r.playUrl != null && r.playUrl!.isNotEmpty) res = r;
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
