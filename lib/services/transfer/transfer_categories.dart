import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show debugPrint;

import '../engine/local_engine_storage.dart';
import '../home_collections_store.dart';
import '../iptv_transfer_payload.dart';
import '../mdblist/mdblist_calendar_service.dart';
import '../mdblist/mdblist_continue_watching_service.dart';
import '../mdblist/mdblist_service.dart';
import '../mdblist/mdblist_sync_coordinator.dart';
import '../pikpak_api_service.dart';
import '../remote_control/remote_constants.dart';
import 'package:debrify/services/storage/tracking_prefs.dart';
import '../storage_service.dart';
import '../stream_badges_service.dart';
import '../stremio_service.dart';
import 'transfer_category.dart';
import 'transfer_restore_helpers.dart';

/// Built-in transfer categories. Order is [TransferCategories.builtins].
class TransferCategories {
  TransferCategories._();

  static const realDebrid = TransferCategory(
    key: 'realDebrid',
    payloadKey: 'realDebridApiKey',
    wireCommand: ConfigCommand.realDebrid,
    label: 'Real-Debrid',
    summarizeLabel: 'Real-Debrid',
    glyph: TransferCategoryGlyph.speed,
    color: Color(0xFF10B981),
    wireEncoding: TransferWireEncoding.rawString,
    remoteBatch: true,
    expectedInProfilePayload: true,
    build: _buildRealDebrid,
    apply: _applyRealDebrid,
    count: _countRealDebrid,
    inspect: _inspectRealDebrid,
    readWire: _readRealDebridWire,
  );

  static const torbox = TransferCategory(
    key: 'torbox',
    payloadKey: 'torboxApiKey',
    wireCommand: ConfigCommand.torbox,
    label: 'Torbox',
    summarizeLabel: 'TorBox',
    glyph: TransferCategoryGlyph.inventory2,
    color: Color(0xFFF59E0B),
    wireEncoding: TransferWireEncoding.rawString,
    remoteBatch: true,
    expectedInProfilePayload: true,
    build: _buildTorbox,
    apply: _applyTorbox,
    count: _countTorbox,
    inspect: _inspectTorbox,
    readWire: _readTorboxWire,
  );

  static const premiumize = TransferCategory(
    key: 'premiumize',
    payloadKey: 'premiumizeApiKey',
    wireCommand: ConfigCommand.premiumize,
    label: 'Premiumize',
    summarizeLabel: 'Premiumize',
    glyph: TransferCategoryGlyph.workspacePremium,
    color: Color(0xFFFB923C),
    wireEncoding: TransferWireEncoding.rawString,
    remoteBatch: true,
    expectedInProfilePayload: true,
    build: _buildPremiumize,
    apply: _applyPremiumize,
    count: _countPremiumize,
    inspect: _inspectPremiumize,
    readWire: _readPremiumizeWire,
  );

  static const allDebrid = TransferCategory(
    key: 'allDebrid',
    payloadKey: 'allDebridApiKey',
    wireCommand: ConfigCommand.allDebrid,
    label: 'AllDebrid',
    summarizeLabel: 'AllDebrid',
    glyph: TransferCategoryGlyph.allInclusive,
    color: Color(0xFF26A69A),
    wireEncoding: TransferWireEncoding.rawString,
    remoteBatch: true,
    expectedInProfilePayload: true,
    build: _buildAllDebrid,
    apply: _applyAllDebrid,
    count: _countAllDebrid,
    inspect: _inspectAllDebrid,
    readWire: _readAllDebridWire,
  );

  static const pikpak = TransferCategory(
    key: 'pikpak',
    payloadKey: 'pikpak',
    wireCommand: ConfigCommand.pikpak,
    label: 'PikPak',
    summarizeLabel: 'PikPak',
    glyph: TransferCategoryGlyph.cloud,
    color: Color(0xFF3B82F6),
    wireEncoding: TransferWireEncoding.json,
    remoteBatch: true,
    expectedInProfilePayload: true,
    build: _buildPikpak,
    apply: _applyPikpak,
    count: _countPikpak,
    inspect: _inspectPikpak,
    readWire: _readPikpakWire,
  );

  static const trakt = TransferCategory(
    key: 'trakt',
    payloadKey: 'trakt',
    wireCommand: ConfigCommand.trakt,
    label: 'Trakt',
    summarizeLabel: 'Trakt',
    glyph: TransferCategoryGlyph.history,
    color: Color(0xFFED1C24),
    wireEncoding: TransferWireEncoding.json,
    remoteBatch: true,
    expectedInProfilePayload: true,
    build: _buildTrakt,
    apply: _applyTrakt,
    count: _countTrakt,
    inspect: _inspectTrakt,
    readWire: _readTraktWire,
  );

  static const simkl = TransferCategory(
    key: 'simkl',
    payloadKey: 'simkl',
    wireCommand: ConfigCommand.simkl,
    label: 'Simkl',
    summarizeLabel: 'Simkl',
    glyph: TransferCategoryGlyph.movieFilter,
    color: Color(0xFF22D3EE),
    wireEncoding: TransferWireEncoding.json,
    remoteBatch: true,
    expectedInProfilePayload: true,
    build: _buildSimkl,
    apply: _applySimkl,
    count: _countSimkl,
    inspect: _inspectSimkl,
    readWire: _readSimklWire,
  );

  static const mdblist = TransferCategory(
    key: 'mdblist',
    payloadKey: 'mdblist',
    wireCommand: ConfigCommand.mdblist,
    label: 'MDBList',
    glyph: TransferCategoryGlyph.listAlt,
    color: Color(0xFF8B5CF6),
    wireEncoding: TransferWireEncoding.json,
    remoteBatch: true,
    expectedInProfilePayload: true,
    build: _buildMdblist,
    apply: _applyMdblist,
    count: _countMdblist,
    inspect: _inspectMdblist,
    readWire: _readMdblistWire,
  );

  static const searchEngines = TransferCategory(
    key: 'searchEngines',
    payloadKey: 'searchEngineIds',
    wireCommand: ConfigCommand.searchEngines,
    label: 'Search Engines',
    summarizeLabel: 'Search engines',
    glyph: TransferCategoryGlyph.search,
    color: Color(0xFF8B5CF6),
    wireEncoding: TransferWireEncoding.json,
    remoteBatch: true,
    expectedInProfilePayload: true,
    build: _buildSearchEngines,
    apply: _applySearchEngines,
    count: _countSearchEngines,
    inspect: _inspectSearchEngines,
    readWire: _readSearchEnginesWire,
  );

  static const addons = TransferCategory(
    key: 'addons',
    payloadKey: 'addonManifestUrls',
    label: 'Stremio addons',
    glyph: TransferCategoryGlyph.extension,
    color: Color(0xFF8B5CF6),
    build: _buildAddons,
    apply: _applyAddons,
    count: _countAddons,
  );

  static const webDav = TransferCategory(
    key: 'webDav',
    payloadKey: 'webDavServers',
    wireCommand: ConfigCommand.webDav,
    label: 'WebDAV',
    summarizeLabel: 'WebDAV servers',
    glyph: TransferCategoryGlyph.dns,
    color: Color(0xFF0EA5E9),
    wireEncoding: TransferWireEncoding.json,
    remoteBatch: true,
    expectedInProfilePayload: true,
    build: _buildWebDav,
    apply: _applyWebDav,
    count: _countWebDav,
    inspect: _inspectWebDav,
    readWire: _readWebDavWire,
  );

  static const indexerManagers = TransferCategory(
    key: 'indexerManagers',
    payloadKey: 'indexerManagers',
    wireCommand: ConfigCommand.indexerManagers,
    label: 'Jackett/Prowlarr',
    summarizeLabel: 'Indexer managers',
    glyph: TransferCategoryGlyph.manageSearch,
    color: Color(0xFFEAB308),
    wireEncoding: TransferWireEncoding.json,
    remoteBatch: true,
    expectedInProfilePayload: true,
    build: _buildIndexerManagers,
    apply: _applyIndexerManagers,
    count: _countIndexerManagers,
    inspect: _inspectIndexerManagers,
    readWire: _readIndexerManagersWire,
  );

  static const iptvPlaylists = TransferCategory(
    key: 'iptvPlaylists',
    payloadKey: 'iptvPlaylists',
    wireCommand: ConfigCommand.iptvPlaylists,
    label: 'IPTV providers',
    summarizeLabel: 'IPTV providers',
    glyph: TransferCategoryGlyph.liveTv,
    color: Color(0xFF14B8A6),
    wireEncoding: TransferWireEncoding.json,
    remoteBatch: true,
    expectedInProfilePayload: true,
    chunkedSend: true,
    build: _buildIptvPlaylists,
    apply: _applyIptvPlaylists,
    count: _countIptvPlaylists,
    inspect: _inspectIptvPlaylists,
    readWire: _readIptvPlaylistsWire,
  );

  static const iptvFavorites = TransferCategory(
    key: 'iptvFavorites',
    payloadKey: 'iptvFavorites',
    wireCommand: ConfigCommand.iptvFavorites,
    label: 'IPTV favorites',
    summarizeLabel: 'IPTV favorites',
    glyph: TransferCategoryGlyph.star,
    color: Color(0xFFF472B6),
    wireEncoding: TransferWireEncoding.json,
    remoteBatch: true,
    expectedInProfilePayload: true,
    chunkedSend: true,
    build: _buildIptvFavorites,
    apply: _applyIptvFavorites,
    count: _countIptvFavorites,
    inspect: _inspectIptvFavorites,
    readWire: _readIptvFavoritesWire,
  );

  static const iptvLists = TransferCategory(
    key: 'iptvLists',
    payloadKey: 'iptvLists',
    wireCommand: ConfigCommand.iptvLists,
    label: 'IPTV lists',
    summarizeLabel: 'IPTV lists',
    glyph: TransferCategoryGlyph.playlistPlay,
    color: Color(0xFFA78BFA),
    wireEncoding: TransferWireEncoding.json,
    remoteBatch: true,
    expectedInProfilePayload: true,
    chunkedSend: true,
    build: _buildIptvLists,
    apply: _applyIptvLists,
    count: _countIptvLists,
    inspect: _inspectIptvLists,
    readWire: _readIptvListsWire,
  );

  static const homeCollections = TransferCategory(
    key: 'homeCollections',
    payloadKey: 'homeCollections',
    label: 'Collections',
    glyph: TransferCategoryGlyph.folderSpecial,
    color: Color(0xFF38BDF8),
    build: _buildHomeCollections,
    apply: _applyHomeCollections,
    count: _countHomeCollections,
  );

  static const streamBadges = TransferCategory(
    key: 'streamBadges',
    payloadKey: 'streamBadges',
    wireCommand: ConfigCommand.streamBadges,
    label: 'Stream badges',
    summarizeLabel: 'Stream badges',
    glyph: TransferCategoryGlyph.sell,
    color: Color(0xFFFBBF24),
    wireEncoding: TransferWireEncoding.json,
    remoteBatch: true,
    expectedInProfilePayload: true,
    chunkedSend: true,
    build: _buildStreamBadges,
    apply: _applyStreamBadges,
    count: _countStreamBadges,
    inspect: _inspectStreamBadges,
    readWire: _readStreamBadgesWire,
  );

  static const trackingPreferences = TransferCategory(
    key: 'trackingPreferences',
    payloadKey: 'trackingPreferences',
    wireCommand: ConfigCommand.trackingPreferences,
    label: 'Tracking preferences',
    glyph: TransferCategoryGlyph.syncAlt,
    color: Color(0xFF38BDF8),
    wireEncoding: TransferWireEncoding.json,
    // Quirk: not in `_remoteBatchCommands` or `payloadKeys`. The packet
    // still travels as a raw body even inside a transactional transfer.
    remoteBatch: false,
    expectedInProfilePayload: false,
    build: _buildTrackingPreferences,
    apply: _applyTrackingPreferences,
    count: _countTrackingPreferences,
    inspect: _inspectTrackingPreferences,
    readWire: _readTrackingPreferencesWire,
  );

  /// Today's applyBackup order. Pin with a test; do not reshuffle.
  static const List<TransferCategory> builtins = [
    realDebrid,
    torbox,
    premiumize,
    allDebrid,
    pikpak,
    trakt,
    simkl,
    mdblist,
    searchEngines,
    addons,
    webDav,
    indexerManagers,
    iptvPlaylists,
    iptvFavorites,
    iptvLists,
    homeCollections,
    streamBadges,
    trackingPreferences,
  ];
}

int _countNonEmptyString(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is String && value.isNotEmpty ? 1 : 0;
}

int _countMapField(Map<String, dynamic> map, String key, String inner) {
  final value = map[key];
  if (value is! Map) return 0;
  final field = value[inner];
  return field is String && field.isNotEmpty ? 1 : 0;
}

int _countListField(Map<String, dynamic> map, String key) =>
    (map[key] as List?)?.length ?? 0;

int _countSearchEngines(Map<String, dynamic> map) =>
    _countListField(map, 'searchEngineIds');
int _countAddons(Map<String, dynamic> map) =>
    _countListField(map, 'addonManifestUrls');
int _countWebDav(Map<String, dynamic> map) =>
    _countListField(map, 'webDavServers');
int _countIndexerManagers(Map<String, dynamic> map) =>
    _countListField(map, 'indexerManagers');
int _countIptvPlaylists(Map<String, dynamic> map) =>
    _countListField(map, 'iptvPlaylists');
int _countIptvFavorites(Map<String, dynamic> map) =>
    _countListField(map, 'iptvFavorites');
int _countIptvLists(Map<String, dynamic> map) =>
    _countListField(map, 'iptvLists');
int _countHomeCollections(Map<String, dynamic> map) =>
    _countListField(map, 'homeCollections');
int _countStreamBadges(Map<String, dynamic> map) =>
    _countListField(map, 'streamBadges');

int _countRealDebrid(Map<String, dynamic> map) =>
    _countNonEmptyString(map, 'realDebridApiKey');
int _countTorbox(Map<String, dynamic> map) =>
    _countNonEmptyString(map, 'torboxApiKey');
int _countPremiumize(Map<String, dynamic> map) =>
    _countNonEmptyString(map, 'premiumizeApiKey');
int _countAllDebrid(Map<String, dynamic> map) =>
    _countNonEmptyString(map, 'allDebridApiKey');
int _countPikpak(Map<String, dynamic> map) =>
    _countMapField(map, 'pikpak', 'email');
int _countTrakt(Map<String, dynamic> map) =>
    _countMapField(map, 'trakt', 'access_token');
int _countSimkl(Map<String, dynamic> map) =>
    _countMapField(map, 'simkl', 'access_token');
int _countMdblist(Map<String, dynamic> map) =>
    _countMapField(map, 'mdblist', 'api_key');
int _countTrackingPreferences(Map<String, dynamic> map) =>
    map['trackingPreferences'] is Map ? 1 : 0;

Future<void> _putSecret(TransferBuildContext ctx, String payloadKey) async {
  final secrets = await ctx.secrets();
  final value = secrets[payloadKey];
  if (value != null) ctx.payload[payloadKey] = value;
}

Future<void> _buildRealDebrid(TransferBuildContext ctx) =>
    _putSecret(ctx, 'realDebridApiKey');
Future<void> _buildTorbox(TransferBuildContext ctx) =>
    _putSecret(ctx, 'torboxApiKey');
Future<void> _buildPremiumize(TransferBuildContext ctx) =>
    _putSecret(ctx, 'premiumizeApiKey');
Future<void> _buildAllDebrid(TransferBuildContext ctx) =>
    _putSecret(ctx, 'allDebridApiKey');

Future<void> _buildPikpak(TransferBuildContext ctx) async {
  final secrets = await ctx.secrets();
  final value = secrets['pikpak'];
  if (value != null) ctx.payload['pikpak'] = value;
}

Future<void> _buildTrakt(TransferBuildContext ctx) async {
  if (!ctx.includeCredentials) return;
  final access = await TrackingPrefs.getTraktAccessToken();
  final refresh = await TrackingPrefs.getTraktRefreshToken();
  if (access == null || access.isEmpty || refresh == null || refresh.isEmpty) {
    return;
  }
  final expiry = await TrackingPrefs.getTraktTokenExpiry();
  final username = await TrackingPrefs.getTraktUsername();
  ctx.payload['trakt'] = <String, dynamic>{
    'access_token': access,
    'refresh_token': refresh,
    if (expiry != null) 'expiry_ms': expiry,
    if (username != null && username.isNotEmpty) 'username': username,
  };
}

Future<void> _buildSimkl(TransferBuildContext ctx) async {
  if (!ctx.includeCredentials) return;
  final access = await TrackingPrefs.getSimklAccessToken();
  if (access == null || access.isEmpty) return;
  final username = await TrackingPrefs.getSimklUsername();
  ctx.payload['simkl'] = <String, dynamic>{
    'access_token': access,
    if (username != null && username.isNotEmpty) 'username': username,
  };
}

Future<void> _buildMdblist(TransferBuildContext ctx) async {
  if (!ctx.includeCredentials) return;
  final apiKey = await TrackingPrefs.getMdblistApiKey();
  if (apiKey == null || apiKey.isEmpty) return;
  final username = await TrackingPrefs.getMdblistUsername();
  final checkpoint = await TrackingPrefs.getMdblistSyncCheckpoint();
  final scrobbleTargets = await ctx.scrobbleTargets();
  ctx.payload['mdblist'] = <String, dynamic>{
    'api_key': apiKey,
    if (username != null && username.isNotEmpty) 'username': username,
    // Retained only as a compatibility field for older Debrify
    // restores. Derive it from the new master; never read the retired
    // preference again after one-time master seeding.
    'sync_catalog_items': scrobbleTargets.contains('mdblist'),
    if (checkpoint != null) 'sync_checkpoint': checkpoint,
  };
}

Future<void> _buildSearchEngines(TransferBuildContext ctx) async {
  await LocalEngineStorage.instance.initialize();
  final engineIds = await LocalEngineStorage.instance.getImportedEngineIds();
  if (engineIds.isNotEmpty) ctx.payload['searchEngineIds'] = engineIds;
}

Future<void> _buildAddons(TransferBuildContext ctx) async {
  if (!ctx.includeCredentials) return;
  // Omitted from credential-free exports: configured manifest URLs
  // routinely embed debrid API keys in the path (Torrentio/Comet-style
  // configure strings), and there is no reliable way to scrub them.
  try {
    // Retain disabled owned addons, but do not bypass settings redaction
    // for borrowed resources: a use-only grant must not turn into an
    // exported configured URL. Redacted empty URLs are omitted below.
    final addons = await StremioService.instance.getAddons(forSettings: true);
    final addonUrls = transferBackupAddonManifestUrls(
      addons.map((addon) => addon.manifestUrl),
    );
    if (addonUrls.isNotEmpty) ctx.payload['addonManifestUrls'] = addonUrls;
  } catch (_) {
    throw StateError('Could not read Stremio addons for backup');
  }
}

Future<void> _buildWebDav(TransferBuildContext ctx) async {
  try {
    final servers = await ProviderCredentialPrefs.getWebDavServers();
    final webDavServers = servers.map((s) {
      final json = s.toTransferJson();
      if (!ctx.includeCredentials) json['password'] = '';
      return json;
    }).toList();
    if (webDavServers.isNotEmpty) ctx.payload['webDavServers'] = webDavServers;
  } catch (_) {
    throw StateError('Could not read WebDAV servers for backup');
  }
}

Future<void> _buildIndexerManagers(TransferBuildContext ctx) async {
  if (!ctx.includeCredentials) return;
  // Omitted entirely from credential-free exports: an entry without its
  // API key is rejected by the restorer, so keeping blanked ones would
  // just advertise a category that always fails to import.
  try {
    final configs = await StorageService.getIndexerManagerConfigs();
    final indexerManagers = configs.map((c) => c.toTransferJson()).toList();
    if (indexerManagers.isNotEmpty) {
      ctx.payload['indexerManagers'] = indexerManagers;
    }
  } catch (_) {
    throw StateError('Could not read indexer managers for backup');
  }
}

Future<void> _buildIptvPlaylists(TransferBuildContext ctx) async {
  final iptv = await ctx.iptv();
  if (iptv.playlists.isNotEmpty) ctx.payload['iptvPlaylists'] = iptv.playlists;
}

Future<void> _buildIptvFavorites(TransferBuildContext ctx) async {
  final iptv = await ctx.iptv();
  if (iptv.favorites.isNotEmpty) ctx.payload['iptvFavorites'] = iptv.favorites;
}

Future<void> _buildIptvLists(TransferBuildContext ctx) async {
  final iptv = await ctx.iptv();
  if (iptv.lists.isNotEmpty) ctx.payload['iptvLists'] = iptv.lists;
}

Future<void> _buildHomeCollections(TransferBuildContext ctx) async {
  try {
    final homeCollections = await HomeCollectionsStore.instance.exportJson();
    if (homeCollections.isNotEmpty) {
      ctx.payload['homeCollections'] = homeCollections;
    }
  } catch (_) {
    throw StateError('Could not read Home collections for backup');
  }
}

Future<void> _buildStreamBadges(TransferBuildContext ctx) async {
  try {
    final streamBadges = await StreamBadgesService.instance.exportJson();
    if (streamBadges.isNotEmpty) {
      ctx.payload['streamBadges'] = streamBadges;
    }
  } catch (_) {
    throw StateError('Could not read stream badge rulesets for backup');
  }
}

Future<void> _buildTrackingPreferences(TransferBuildContext ctx) async {
  ctx.payload['trackingPreferences'] = await ctx.trackingPreferences();
}

Future<void> _applyRealDebrid(TransferApplyContext ctx) async {
  final key = ctx.map['realDebridApiKey'] as String?;
  if (key != null && key.isNotEmpty) {
    try {
      await StorageService.saveApiKey(key);
      await ProviderCredentialPrefs.setRealDebridIntegrationEnabled(true);
      ctx.report.realDebrid = true;
    } catch (_) {
      ctx.report.errors.add('Real-Debrid: restore failed');
    }
  }
}

Future<void> _applyTorbox(TransferApplyContext ctx) async {
  final key = ctx.map['torboxApiKey'] as String?;
  if (key != null && key.isNotEmpty) {
    try {
      await StorageService.saveTorboxApiKey(key);
      await ProviderCredentialPrefs.setTorboxIntegrationEnabled(true);
      ctx.report.torbox = true;
    } catch (_) {
      ctx.report.errors.add('Torbox: restore failed');
    }
  }
}

Future<void> _applyPremiumize(TransferApplyContext ctx) async {
  final key = ctx.map['premiumizeApiKey'] as String?;
  if (key != null && key.isNotEmpty) {
    try {
      await StorageService.savePremiumizeApiKey(key);
      await ProviderCredentialPrefs.setPremiumizeIntegrationEnabled(true);
      ctx.report.premiumize = true;
    } catch (_) {
      ctx.report.errors.add('Premiumize: restore failed');
    }
  }
}

Future<void> _applyAllDebrid(TransferApplyContext ctx) async {
  final key = ctx.map['allDebridApiKey'] as String?;
  if (key != null && key.isNotEmpty) {
    try {
      await StorageService.saveAllDebridApiKey(key);
      await ProviderCredentialPrefs.setAllDebridIntegrationEnabled(true);
      ctx.report.allDebrid = true;
    } catch (_) {
      ctx.report.errors.add('AllDebrid: restore failed');
    }
  }
}

Future<void> _applyPikpak(TransferApplyContext ctx) async {
  final pp = ctx.map['pikpak'];
  if (pp is Map) {
    final email = pp['email'] as String?;
    final password = pp['password'] as String?;
    if (email != null && email.isNotEmpty) {
      try {
        await StorageService.setPikPakEmail(email);
        if (password != null && password.isNotEmpty) {
          await StorageService.setPikPakPassword(password);
        }
        await ProviderCredentialPrefs.setPikPakEnabled(true);
        // PikPak needs an active session, not just stored credentials —
        // run a real login so isAuthenticated() returns true after
        // restore. If it fails (e.g. offline), the credentials remain
        // saved so the user can retry from PikPak settings.
        if (password != null && password.isNotEmpty) {
          try {
            final loggedIn = await PikPakApiService.instance.login(
              email,
              password,
            );
            ctx.report.pikpak = loggedIn;
            if (!loggedIn) {
              ctx.report.pikpakLoginFailed = true;
            }
          } catch (_) {
            ctx.report.pikpakLoginFailed = true;
            debugPrint('BackupRestoreService: PikPak login failed');
          }
        } else {
          // No password in backup — credentials saved but can't log in.
          ctx.report.pikpak = true;
          ctx.report.pikpakLoginFailed = true;
        }
      } catch (_) {
        ctx.report.errors.add('PikPak: restore failed');
      }
    }
  }
}

Future<void> _applyTrakt(TransferApplyContext ctx) async {
  final t = ctx.map['trakt'];
  if (t is Map) {
    final access = t['access_token'] as String?;
    final refresh = t['refresh_token'] as String?;
    if (access != null &&
        access.isNotEmpty &&
        refresh != null &&
        refresh.isNotEmpty) {
      try {
        await TrackingPrefs.setTraktAccessToken(access);
        await TrackingPrefs.setTraktRefreshToken(refresh);
        final expiry = (t['expiry_ms'] as num?)?.toInt();
        if (expiry != null) {
          await TrackingPrefs.setTraktTokenExpiry(expiry);
        }
        final username = t['username'] as String?;
        if (username != null && username.isNotEmpty) {
          await TrackingPrefs.setTraktUsername(username);
        }
        // Match interactive connect: a freshly imported Trakt session
        // starts with catalog scrobbling on.
        await TrackingPrefs.setTraktSyncCatalogItems(true);
        ctx.report.trakt = true;
      } catch (_) {
        ctx.report.errors.add('Trakt: restore failed');
      }
    }
  }
}

Future<void> _applySimkl(TransferApplyContext ctx) async {
  final s = ctx.map['simkl'];
  if (s is Map) {
    final access = s['access_token'] as String?;
    if (access != null && access.isNotEmpty) {
      try {
        await TrackingPrefs.setSimklAccessToken(access);
        final username = s['username'] as String?;
        if (username != null && username.isNotEmpty) {
          await TrackingPrefs.setSimklUsername(username);
        }
        // Match interactive connect: a freshly imported Simkl session
        // starts with catalog scrobbling on.
        await TrackingPrefs.setSimklSyncCatalogItems(true);
        ctx.report.simkl = true;
      } catch (_) {
        ctx.report.errors.add('Simkl: restore failed');
      }
    }
  }
}

Future<void> _applyMdblist(TransferApplyContext ctx) async {
  final m = ctx.map['mdblist'];
  if (m is Map) {
    final apiKey = m['api_key'] as String?;
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        await TrackingPrefs.saveMdblistApiKey(apiKey);
        final username = m['username'] as String?;
        await TrackingPrefs.setMdblistUsername(username);
        await TrackingPrefs.setMdblistSyncCatalogItems(
          m['sync_catalog_items'] as bool? ?? true,
        );
        final checkpoint = m['sync_checkpoint'];
        await TrackingPrefs.setMdblistSyncCheckpoint(
          checkpoint is Map ? Map<String, dynamic>.from(checkpoint) : null,
        );
        // The key was written directly (not via connect()), so the MDBList
        // services still hold the previous account's response caches —
        // drop them or restored credentials serve the old account's
        // watched/library/CW data for up to the cache TTLs. Mirrors the
        // MDBList subset of the profile-switch reset list in
        // profile_app_lifecycle_participant.dart.
        MdblistService.instance.resetProfileScope();
        MdblistContinueWatchingService.instance.resetProfileScope();
        MdblistCalendarService.instance.resetProfileScope();
        MdblistSyncCoordinator.instance.resetProfileScope();
        ctx.report.mdblist = true;
      } catch (_) {
        ctx.report.errors.add('MDBList: restore failed');
      }
    }
  }
}

Future<void> _applySearchEngines(TransferApplyContext ctx) async {
  final ids = (ctx.map['searchEngineIds'] as List?)?.cast<String>() ?? const [];
  if (ids.isNotEmpty) {
    await restoreSearchEngines(
      ids,
      ctx.report,
      refreshRuntime: ctx.refreshEngineRuntime,
    );
  }
}

Future<void> _applyAddons(TransferApplyContext ctx) async {
  final urls =
      (ctx.map['addonManifestUrls'] as List?)?.cast<String>() ?? const [];
  if (urls.isNotEmpty) {
    await restoreAddons(urls, ctx.report);
  }
}

Future<void> _applyWebDav(TransferApplyContext ctx) async {
  final list = ctx.map['webDavServers'];
  if (list is List && list.isNotEmpty) {
    await restoreWebDavServers(list, ctx.report);
  }
}

Future<void> _applyIndexerManagers(TransferApplyContext ctx) async {
  final list = ctx.map['indexerManagers'];
  if (list is List && list.isNotEmpty) {
    await restoreIndexerManagers(list, ctx.report);
  }
}

Future<void> _applyIptvPlaylists(TransferApplyContext ctx) async {
  final list = ctx.map['iptvPlaylists'];
  if (list is List && list.isNotEmpty) {
    final counts = await IptvTransferPayload.applyPlaylists(list);
    ctx.report.iptvPlaylistsImported = counts.imported;
    ctx.report.iptvPlaylistsAlreadyPresent = counts.alreadyPresent;
    ctx.report.iptvPlaylistsFailed = counts.failed;
    if (counts.error != null) {
      ctx.report.errors.add('IPTV providers: ${counts.error}');
    }
  }
}

Future<void> _applyIptvFavorites(TransferApplyContext ctx) async {
  final list = ctx.map['iptvFavorites'];
  if (list is List && list.isNotEmpty) {
    final counts = await IptvTransferPayload.applyFavorites(list);
    ctx.report.iptvFavoritesImported = counts.channelsImported;
    ctx.report.iptvFavoritesAlreadyPresent = counts.channelsAlreadyPresent;
    ctx.report.iptvFavoritesFailed = counts.failed;
    if (counts.error != null) {
      ctx.report.errors.add('IPTV favorites: ${counts.error}');
    }
  }
}

Future<void> _applyIptvLists(TransferApplyContext ctx) async {
  final list = ctx.map['iptvLists'];
  if (list is List && list.isNotEmpty) {
    final counts = await IptvTransferPayload.applyCustomLists(list);
    ctx.report.iptvListsCreated = counts.imported;
    ctx.report.iptvListsMerged = counts.alreadyPresent;
    ctx.report.iptvListChannelsImported = counts.channelsImported;
    ctx.report.iptvListChannelsAlreadyPresent = counts.channelsAlreadyPresent;
    ctx.report.iptvListsFailed = counts.failed;
    if (counts.error != null) {
      ctx.report.errors.add('IPTV lists: ${counts.error}');
    }
  }
}

Future<void> _applyHomeCollections(TransferApplyContext ctx) async {
  final list = ctx.map['homeCollections'];
  if (list is List && list.isNotEmpty) {
    try {
      final counts = await HomeCollectionsStore.instance.applyBackup(list);
      ctx.report.homeCollectionsImported = counts.imported;
      ctx.report.homeCollectionsAlreadyPresent = counts.alreadyPresent;
      ctx.report.homeCollectionsFailed = counts.failed;
    } catch (_) {
      ctx.report.errors.add('Collections: restore failed');
    }
  }
}

Future<void> _applyStreamBadges(TransferApplyContext ctx) async {
  final list = ctx.map['streamBadges'];
  if (list is List && list.isNotEmpty) {
    try {
      final counts = await StreamBadgesService.instance.applyBackup(list);
      ctx.report.streamBadgeSourcesImported = counts.imported;
      ctx.report.streamBadgeSourcesAlreadyPresent = counts.alreadyPresent;
      ctx.report.streamBadgeSourcesFailed = counts.failed;
    } catch (_) {
      ctx.report.errors.add('Stream badges: restore failed');
    }
  }
}

Future<void> _applyTrackingPreferences(TransferApplyContext ctx) async {
  final trackingPreferences = ctx.map['trackingPreferences'];
  if (trackingPreferences is Map) {
    try {
      await TrackingPrefs.applyTrackingPreferencesPayload(trackingPreferences);
    } catch (_) {
      ctx.report.errors.add('Tracking preferences: restore failed');
    }
  }
}

Future<TransferInventory> _inspectKey({
  required Future<String?> Function({bool forRemoteTransfer}) read,
  required Future<bool> Function() enabled,
}) async {
  final key = await read(forRemoteTransfer: true);
  final on = await enabled();
  final ok = key != null && key.isNotEmpty && on;
  return TransferInventory(isConfigured: ok, defaultSelected: ok);
}

Future<TransferInventory> _inspectRealDebrid() => _inspectKey(
  read: StorageService.getApiKey,
  enabled: ProviderCredentialPrefs.getRealDebridIntegrationEnabled,
);
Future<TransferInventory> _inspectTorbox() => _inspectKey(
  read: StorageService.getTorboxApiKey,
  enabled: ProviderCredentialPrefs.getTorboxIntegrationEnabled,
);
Future<TransferInventory> _inspectPremiumize() => _inspectKey(
  read: StorageService.getPremiumizeApiKey,
  enabled: ProviderCredentialPrefs.getPremiumizeIntegrationEnabled,
);
Future<TransferInventory> _inspectAllDebrid() => _inspectKey(
  read: StorageService.getAllDebridApiKey,
  enabled: ProviderCredentialPrefs.getAllDebridIntegrationEnabled,
);

Future<TransferInventory> _inspectPikpak() async {
  final email = await StorageService.getPikPakEmail(forRemoteTransfer: true);
  final enabled = await ProviderCredentialPrefs.getPikPakEnabled();
  final ok = email != null && email.isNotEmpty && enabled;
  // Password must be typed on Send Setup to TV.
  return TransferInventory(isConfigured: ok, defaultSelected: false);
}

Future<TransferInventory> _inspectTrakt() async {
  final access = await TrackingPrefs.getTraktAccessToken(
    forRemoteTransfer: true,
  );
  final refresh = await TrackingPrefs.getTraktRefreshToken(
    forRemoteTransfer: true,
  );
  final username = await TrackingPrefs.getTraktUsername();
  final ok =
      access != null &&
      access.isNotEmpty &&
      refresh != null &&
      refresh.isNotEmpty;
  return TransferInventory(
    isConfigured: ok,
    defaultSelected: ok,
    accountLabel: username,
  );
}

Future<TransferInventory> _inspectSimkl() async {
  final access = await TrackingPrefs.getSimklAccessToken(
    forRemoteTransfer: true,
  );
  final username = await TrackingPrefs.getSimklUsername();
  final ok = access != null && access.isNotEmpty;
  return TransferInventory(
    isConfigured: ok,
    defaultSelected: ok,
    accountLabel: username,
  );
}

Future<TransferInventory> _inspectMdblist() async {
  if (!kMdblistEnabled) {
    return const TransferInventory(isConfigured: false, defaultSelected: false);
  }
  final apiKey = await TrackingPrefs.getMdblistApiKey(forRemoteTransfer: true);
  final username = await TrackingPrefs.getMdblistUsername();
  final ok = apiKey?.isNotEmpty ?? false;
  return TransferInventory(
    isConfigured: ok,
    defaultSelected: ok,
    accountLabel: username,
  );
}

Future<TransferInventory> _inspectSearchEngines() async {
  await LocalEngineStorage.instance.initialize();
  final n = (await LocalEngineStorage.instance.getImportedEngineIds()).length;
  return TransferInventory(
    isConfigured: n > 0,
    defaultSelected: n > 0,
    count: n,
  );
}

Future<TransferInventory> _inspectWebDav() async {
  try {
    final n = (await ProviderCredentialPrefs.getWebDavServers(
      forSettings: false,
      forRemoteTransfer: true,
    )).length;
    return TransferInventory(
      isConfigured: n > 0,
      defaultSelected: n > 0,
      count: n,
    );
  } catch (_) {
    debugPrint('RemoteConfigExport: WebDAV inventory failed');
    return const TransferInventory(isConfigured: false, defaultSelected: false);
  }
}

Future<TransferInventory> _inspectIndexerManagers() async {
  try {
    final n = (await StorageService.getIndexerManagerConfigs(
      forSettings: false,
      forRemoteTransfer: true,
    )).length;
    return TransferInventory(
      isConfigured: n > 0,
      defaultSelected: n > 0,
      count: n,
    );
  } catch (_) {
    debugPrint('RemoteConfigExport: indexer inventory failed');
    return const TransferInventory(isConfigured: false, defaultSelected: false);
  }
}

Future<TransferInventory> _inspectIptvPlaylists() async {
  try {
    final n = (await IptvTransferPayload.buildPlaylists(
      forRemoteTransfer: true,
    )).length;
    return TransferInventory(
      isConfigured: n > 0,
      defaultSelected: n > 0,
      count: n,
    );
  } catch (_) {
    return const TransferInventory(isConfigured: false, defaultSelected: false);
  }
}

Future<TransferInventory> _inspectIptvFavorites() async {
  try {
    final n = (await IptvTransferPayload.buildFavorites(
      forRemoteTransfer: true,
    )).length;
    return TransferInventory(
      isConfigured: n > 0,
      defaultSelected: n > 0,
      count: n,
    );
  } catch (_) {
    return const TransferInventory(isConfigured: false, defaultSelected: false);
  }
}

Future<TransferInventory> _inspectIptvLists() async {
  try {
    final lists = await IptvTransferPayload.buildCustomLists(
      forRemoteTransfer: true,
    );
    final n = lists.length;
    return TransferInventory(
      isConfigured: n > 0,
      defaultSelected: n > 0,
      count: n,
    );
  } catch (_) {
    return const TransferInventory(isConfigured: false, defaultSelected: false);
  }
}

Future<TransferInventory> _inspectStreamBadges() async {
  try {
    final n = (await StreamBadgesService.instance.getSources()).length;
    return TransferInventory(
      isConfigured: n > 0,
      defaultSelected: n > 0,
      count: n,
    );
  } catch (_) {
    debugPrint('RemoteTransferAll: stream badge inventory failed');
    return const TransferInventory(isConfigured: false, defaultSelected: false);
  }
}

Future<TransferInventory> _inspectTrackingPreferences() async =>
    const TransferInventory(isConfigured: true, defaultSelected: true);

Future<Object?> _readRealDebridWire(TransferSendContext ctx) =>
    StorageService.getApiKey(forRemoteTransfer: ctx.forRemoteTransfer);
Future<Object?> _readTorboxWire(TransferSendContext ctx) =>
    StorageService.getTorboxApiKey(forRemoteTransfer: ctx.forRemoteTransfer);
Future<Object?> _readPremiumizeWire(TransferSendContext ctx) =>
    StorageService.getPremiumizeApiKey(
      forRemoteTransfer: ctx.forRemoteTransfer,
    );
Future<Object?> _readAllDebridWire(TransferSendContext ctx) =>
    StorageService.getAllDebridApiKey(forRemoteTransfer: ctx.forRemoteTransfer);

Future<Object?> _readPikpakWire(TransferSendContext ctx) async {
  final email = await StorageService.getPikPakEmail(
    forRemoteTransfer: ctx.forRemoteTransfer,
  );
  if (email == null || email.isEmpty) {
    return null;
  }
  // Origin senders (Send Setup to TV + Transfer Everything) encoded
  // `{email}` when the typed password was empty; only a missing email
  // skipped the item. Do not require a non-empty password here.
  final password = ctx.pikpakPassword;
  return <String, Object?>{
    'email': email,
    if (password != null && password.isNotEmpty) 'password': password,
  };
}

Future<Object?> _readTraktWire(TransferSendContext ctx) async {
  final access = await TrackingPrefs.getTraktAccessToken(
    forRemoteTransfer: ctx.forRemoteTransfer,
  );
  final refresh = await TrackingPrefs.getTraktRefreshToken(
    forRemoteTransfer: ctx.forRemoteTransfer,
  );
  if (access == null || access.isEmpty || refresh == null || refresh.isEmpty) {
    return null;
  }
  final expiry = await TrackingPrefs.getTraktTokenExpiry();
  final username = await TrackingPrefs.getTraktUsername();
  return <String, Object?>{
    'access_token': access,
    'refresh_token': refresh,
    if (expiry != null) 'expiry_ms': expiry,
    if (username != null) 'username': username,
  };
}

Future<Object?> _readSimklWire(TransferSendContext ctx) async {
  final access = await TrackingPrefs.getSimklAccessToken(
    forRemoteTransfer: ctx.forRemoteTransfer,
  );
  if (access == null || access.isEmpty) return null;
  final username = await TrackingPrefs.getSimklUsername();
  return <String, Object?>{
    'access_token': access,
    if (username != null) 'username': username,
  };
}

Future<Object?> _readMdblistWire(TransferSendContext ctx) async {
  final apiKey = await TrackingPrefs.getMdblistApiKey(
    forRemoteTransfer: ctx.forRemoteTransfer,
  );
  if (apiKey == null || apiKey.isEmpty) return null;
  final username = await TrackingPrefs.getMdblistUsername();
  return <String, Object?>{
    'api_key': apiKey,
    if (username != null) 'username': username,
  };
}

Future<Object?> _readSearchEnginesWire(TransferSendContext ctx) async {
  await LocalEngineStorage.instance.initialize();
  final engineIds = await LocalEngineStorage.instance.getImportedEngineIds();
  return engineIds.isEmpty ? null : engineIds;
}

Future<Object?> _readWebDavWire(TransferSendContext ctx) async {
  final servers = await ProviderCredentialPrefs.getWebDavServers(
    forSettings: false,
    forRemoteTransfer: ctx.forRemoteTransfer,
  );
  if (servers.isEmpty) return null;
  return [for (final server in servers) server.toTransferJson()];
}

Future<Object?> _readIndexerManagersWire(TransferSendContext ctx) async {
  final managers = await StorageService.getIndexerManagerConfigs(
    forSettings: false,
    forRemoteTransfer: ctx.forRemoteTransfer,
  );
  if (managers.isEmpty) return null;
  return [for (final manager in managers) manager.toTransferJson()];
}

Future<Object?> _readIptvPlaylistsWire(TransferSendContext ctx) async {
  final payload = await IptvTransferPayload.buildPlaylists(
    forRemoteTransfer: ctx.forRemoteTransfer,
  );
  return payload.isEmpty ? null : payload;
}

Future<Object?> _readIptvFavoritesWire(TransferSendContext ctx) async {
  final payload = await IptvTransferPayload.buildFavorites(
    forRemoteTransfer: ctx.forRemoteTransfer,
  );
  return payload.isEmpty ? null : payload;
}

Future<Object?> _readIptvListsWire(TransferSendContext ctx) async {
  final payload = await IptvTransferPayload.buildCustomLists(
    forRemoteTransfer: ctx.forRemoteTransfer,
  );
  return payload.isEmpty ? null : payload;
}

Future<Object?> _readStreamBadgesWire(TransferSendContext ctx) async {
  final payload = await StreamBadgesService.instance.exportJson();
  return payload.isEmpty ? null : payload;
}

Future<Object?> _readTrackingPreferencesWire(TransferSendContext ctx) =>
    TrackingPrefs.buildTrackingPreferencesPayload();
