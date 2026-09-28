import 'dart:convert';

import '../../../models/playlist_entry.dart';
import '../../../services/alldebrid_service.dart';
import '../../../services/debrid_service.dart';
import '../../../services/download_service.dart';
import '../../../services/premiumize_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';
import '../../../services/torbox_service.dart';
import 'source_acquisition_cleanup.dart';

typedef ProviderDownloadRequest = ({
  String url,
  String fileName,
  String torrentName,
  String? credentialKey,
  String? meta,
});

/// Explicit post-acquisition actions retain the source's original account.
/// Accepted device/provider downloads outlive the view; later work does not.
class ProviderSourceActions {
  const ProviderSourceActions({
    required this.owner,
    required this.canContinue,
    this.enqueue = _enqueue,
  });
  final ProfileSessionOwner owner;
  final bool Function() canContinue;
  final Future<void> Function(ProviderDownloadRequest, bool Function()) enqueue;
  bool get isCurrent =>
      owner == ProfileSessionMemory.captureOwner() && canContinue();
  void _check() {
    if (!isCurrent) throw StateError('Source action retired');
  }

  Future<T> _owned<T>(Future<T> Function() action) async {
    _check();
    final scope = owner.scope;
    return scope == null
        ? ProfileRuntime.withoutCapturedScope(action)
        : ProfileRuntime.withCapturedScope(scope, action);
  }

  static Future<void> _enqueue(
    ProviderDownloadRequest request,
    bool Function() active,
  ) async {
    await DownloadService.instance.enqueueDownload(
      url: request.url,
      fileName: request.fileName,
      torrentName: request.torrentName,
      credentialKey: request.credentialKey,
      meta: request.meta,
      canContinue: active,
    );
  }

  static String? credentialKey(String provider) => switch (provider) {
    'debrid' || 'realdebrid' => 'real_debrid_api_key',
    'torbox' => 'torbox_api_key',
    'premiumize' => 'premiumize_api_key',
    'alldebrid' => 'alldebrid_api_key',
    'pikpak' => 'pikpak_email',
    _ => null,
  };

  Future<void> queueUrl(
    String url, {
    required String provider,
    required String fileName,
    required String torrentName,
    String? meta,
  }) => _owned(() async {
    _check();
    await enqueue((
      url: url,
      fileName: fileName,
      torrentName: torrentName,
      credentialKey: credentialKey(provider),
      meta: meta,
    ), () => isCurrent);
  });

  Future<int> queueEntries(
    List<PlaylistEntry> entries, {
    required String provider,
    required String torrentName,
  }) => _owned(() async {
    var queued = 0;
    for (final entry in entries) {
      if (!isCurrent) break;
      final url = await _resolveEntry(entry);
      if (!isCurrent) break;
      if (url == null || url.isEmpty) continue;
      try {
        await queueUrl(
          url,
          provider: provider,
          fileName: entry.title,
          torrentName: torrentName,
        );
        queued++;
      } catch (_) {}
    }
    return queued;
  });

  Future<String?> _resolveEntry(PlaylistEntry entry) async {
    if (entry.url.isNotEmpty) return entry.url;
    try {
      if (entry.restrictedLink?.isNotEmpty == true) {
        final key =
            (await StorageService.getApiKey(canContinue: () => isCurrent)) ??
            '';
        _check();
        final result = await DebridService.unrestrictLink(
          key,
          entry.restrictedLink!,
          canContinue: () => isCurrent,
        );
        return result['download']?.toString();
      }
      if (entry.torboxTorrentId != null && entry.torboxFileId != null) {
        final key =
            (await StorageService.getTorboxApiKey(
              canContinue: () => isCurrent,
            )) ??
            '';
        _check();
        return await TorboxService.requestFileDownloadLink(
          apiKey: key,
          torrentId: entry.torboxTorrentId!,
          fileId: entry.torboxFileId!,
          canContinue: () => isCurrent,
        );
      }
      if (entry.allDebridLink?.isNotEmpty == true) {
        final key =
            (await StorageService.getAllDebridApiKey(
              canContinue: () => isCurrent,
            )) ??
            '';
        _check();
        return await AllDebridService.unlockLink(
          key,
          entry.allDebridLink!,
          canContinue: () => isCurrent,
        );
      }
    } catch (_) {}
    return null;
  }

  Future<String?> torboxZipUrl(int torrentId) => _owned(() async {
    final key =
        (await StorageService.getTorboxApiKey(canContinue: () => isCurrent)) ??
        '';
    _check();
    return key.isEmpty
        ? null
        : TorboxService.createZipPermalink(key, torrentId);
  });

  Future<bool> queueTorboxZip(int torrentId, String name) => _owned(() async {
    final url = await torboxZipUrl(torrentId);
    _check();
    if (url == null) return false;
    await queueUrl(
      url,
      provider: 'torbox',
      fileName: '$name.zip',
      torrentName: name,
      meta: jsonEncode({
        'torboxDownload': true,
        'torboxZip': true,
        'torboxTorrentId': torrentId,
      }),
    );
    return true;
  });

  Future<bool> transferPremiumize(String magnet) => _owned(() async {
    final key =
        (await StorageService.getPremiumizeApiKey(
          canContinue: () => isCurrent,
        )) ??
        '';
    _check();
    if (key.isEmpty) return false;
    await PremiumizeService.createTransfer(key, magnet);
    return true;
  });

  Future<String?> premiumizeZipUrl(
    String magnet, {
    void Function()? onStarted,
  }) => _owned(() async {
    final key =
        (await StorageService.getPremiumizeApiKey(
          canContinue: () => isCurrent,
        )) ??
        '';
    _check();
    if (key.isEmpty) return null;
    onStarted?.call();
    _check();
    final url = await PremiumizeService.createTransferAndGenerateZip(
      key,
      magnet,
      canContinue: () => isCurrent,
    );
    _check();
    return url;
  });

  Future<void> decideNotCached(
    Object marker,
    String provider,
    String magnet, {
    required bool keep,
  }) => _owned(() async {
    if (!keep) {
      await cleanupRejectedSource(marker, owner: owner);
      return;
    }
    // RD/AllDebrid already added the item; only these two need a new request.
    if (provider == 'torbox') {
      final key =
          (await StorageService.getTorboxApiKey(
            canContinue: () => isCurrent,
          )) ??
          '';
      _check();
      try {
        await TorboxService.createTorrent(
          apiKey: key,
          magnet: magnet,
          addOnlyIfCached: false,
          canContinue: () => isCurrent,
        );
      } catch (_) {}
    } else if (provider == 'premiumize') {
      final key =
          (await StorageService.getPremiumizeApiKey(
            canContinue: () => isCurrent,
          )) ??
          '';
      _check();
      try {
        await PremiumizeService.createTransfer(key, magnet);
      } catch (_) {}
    }
  });
}
