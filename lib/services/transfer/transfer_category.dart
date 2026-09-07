import 'dart:ui' show Color;

import '../cloud/cloud_credentials.dart';
import '../iptv_transfer_payload.dart';
import 'package:debrify/services/storage/tracking_prefs.dart';
import 'backup_models.dart';

/// How a category travels on the remote config wire.
enum TransferWireEncoding {
  /// API keys: the payload is the raw string.
  rawString,

  /// JSON-encoded object or list.
  json,
}

/// Which glyph a category shows in transfer / backup pickers.
///
/// A semantic id rather than an `IconData`, so the service layer stays free of
/// Flutter widgets; `lib/widgets/transfer/transfer_category_chrome.dart` maps
/// each value to its Material icon. Names follow the Material icon they map to.
enum TransferCategoryGlyph {
  speed,
  inventory2,
  workspacePremium,
  allInclusive,
  cloud,
  history,
  movieFilter,
  listAlt,
  search,
  extension,
  dns,
  manageSearch,
  liveTv,
  star,
  playlistPlay,
  folderSpecial,
  sell,
  syncAlt,
}

/// One backup / remote-transfer / profile-restore category.
///
/// Built-ins are const so [BackupSelection]'s named constructor can stay
/// const for unowned callers. Tests register extra instances via
/// [TransferCategoryRegistry.register].
///
/// [glyph] and [color] are pure presentation data; the `icon` getter lives in
/// the widgets layer (`TransferCategoryChrome`).
class TransferCategory {
  final String key;
  final String payloadKey;
  final String? wireCommand;
  final String label;
  final String? summarizeLabel;
  final TransferCategoryGlyph glyph;
  final Color color;
  final TransferWireEncoding? wireEncoding;
  final bool remoteBatch;
  final bool expectedInProfilePayload;
  final bool chunkedSend;
  final TransferBuild build;
  final TransferApply apply;
  final TransferCount count;
  final TransferInspect? inspect;
  final TransferReadWire? readWire;

  const TransferCategory({
    required this.key,
    required this.payloadKey,
    this.wireCommand,
    required this.label,
    this.summarizeLabel,
    required this.glyph,
    required this.color,
    this.wireEncoding,
    this.remoteBatch = false,
    this.expectedInProfilePayload = false,
    this.chunkedSend = false,
    required this.build,
    required this.apply,
    required this.count,
    this.inspect,
    this.readWire,
  });

  bool get hasWire => wireCommand != null;
}

typedef TransferBuild = Future<void> Function(TransferBuildContext ctx);
typedef TransferApply = Future<void> Function(TransferApplyContext ctx);
typedef TransferCount = int Function(Map<String, dynamic> map);
typedef TransferInspect = Future<TransferInventory> Function();
typedef TransferReadWire = Future<Object?> Function(TransferSendContext ctx);

class TransferInventory {
  final bool isConfigured;
  final bool defaultSelected;
  final int count;
  final String? accountLabel;

  const TransferInventory({
    required this.isConfigured,
    required this.defaultSelected,
    this.count = 0,
    this.accountLabel,
  });
}

class TransferSendContext {
  final String? pikpakPassword;
  final bool forRemoteTransfer;

  const TransferSendContext({
    this.pikpakPassword,
    this.forRemoteTransfer = true,
  });
}

class TransferApplyContext {
  final Map<String, dynamic> map;
  final RestoreReport report;
  final bool refreshEngineRuntime;

  TransferApplyContext({
    required this.map,
    required this.report,
    required this.refreshEngineRuntime,
  });
}

class TransferBuildContext {
  TransferBuildContext({required this.includeCredentials});

  final bool includeCredentials;
  final Map<String, dynamic> payload = <String, dynamic>{};

  Map<String, dynamic>? _secrets;
  Map<String, dynamic>? _tracking;
  Set<String>? _scrobbleTargets;
  TransferIptvSnapshot? _iptv;
  Object? _iptvError;

  Future<Map<String, dynamic>> secrets() async {
    return _secrets ??= includeCredentials
        ? await CloudCredentials.backupSecrets()
        : const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> trackingPreferences() async {
    return _tracking ??= await TrackingPrefs.buildTrackingPreferencesPayload();
  }

  Future<Set<String>> scrobbleTargets() async {
    if (_scrobbleTargets != null) return _scrobbleTargets!;
    final prefs = await trackingPreferences();
    _scrobbleTargets = (prefs['scrobble_targets'] as List)
        .map((value) => value.toString())
        .toSet();
    return _scrobbleTargets!;
  }

  Future<TransferIptvSnapshot> iptv() async {
    if (_iptvError != null) {
      throw _iptvError!;
    }
    if (_iptv != null) return _iptv!;
    try {
      var playlists = await IptvTransferPayload.buildPlaylists();
      var favorites = <Map<String, dynamic>>[];
      var lists = <Map<String, dynamic>>[];
      if (!includeCredentials) {
        // Xtream providers are dropped whole: every field that could travel
        // (`url`, `epgUrl`) embeds the account, and an entry stripped of its
        // url fails to restore. Plain-M3U providers are kept with their url
        // intact — there the URL IS the config, which the export dialog
        // documents.
        playlists.removeWhere(
          (p) => (p['serverUrl'] as String?)?.isNotEmpty == true,
        );
        for (final playlist in playlists) {
          playlist.remove('username');
          playlist.remove('password');
        }
      }
      if (includeCredentials) {
        // Favorite/list entries carry per-channel STREAM URLs, which for
        // Xtream providers embed the account password in the path — they
        // cannot be scrubbed without breaking them, so credential-free
        // exports leave the whole category out.
        favorites = await IptvTransferPayload.buildFavorites();
        lists = await IptvTransferPayload.buildCustomLists();
      }
      return _iptv = TransferIptvSnapshot(
        playlists: playlists,
        favorites: favorites,
        lists: lists,
      );
    } catch (_) {
      _iptvError = StateError('Could not read IPTV setup for backup');
      throw _iptvError!;
    }
  }
}

class TransferIptvSnapshot {
  final List<Map<String, dynamic>> playlists;
  final List<Map<String, dynamic>> favorites;
  final List<Map<String, dynamic>> lists;

  const TransferIptvSnapshot({
    required this.playlists,
    required this.favorites,
    required this.lists,
  });
}
