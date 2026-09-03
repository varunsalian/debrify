import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../models/indexer_manager_config.dart';
import '../models/webdav_item.dart';
import 'engine/config_loader.dart';
import 'engine/engine_registry.dart';
import 'engine/local_engine_storage.dart';
import 'engine/remote_engine_manager.dart';
import 'iptv_transfer_payload.dart';
import 'mdblist/mdblist_calendar_service.dart';
import 'mdblist/mdblist_continue_watching_service.dart';
import 'mdblist/mdblist_service.dart';
import 'mdblist/mdblist_sync_coordinator.dart';
import 'pikpak_api_service.dart';
import 'storage_service.dart';
import 'stream_badges_service.dart';
import 'stremio_service.dart';

/// Service for creating and applying configuration backups.
///
/// The backup payload mirrors what the Remote feature's "Transfer Everything"
/// flow sends over UDP, but assembled into a single JSON document suitable
/// for writing to a file. Categories covered:
///   - Real-Debrid API key
///   - Torbox API key
///   - Premiumize API key
///   - PikPak credentials (email + password)
///   - Trakt session (access, refresh, expiry, username)
///   - Simkl session (access token, username — no refresh/expiry, Simkl
///     tokens don't expire)
///   - Search engine IDs (restore re-downloads YAML from the remote registry)
///   - Stremio addon manifest URLs (restore re-fetches manifests)
///   - WebDAV servers (URL + credentials, may be LAN-only)
///   - Indexer managers (Jackett / Prowlarr — URL + API key, may be LAN-only)
///   - IPTV providers (M3U URLs and Xtream server + credentials), including
///     their manual category order and default landing category. Playlists
///     imported from a file are NOT included — their definition is the raw
///     M3U text, which would bloat the file past the size restore will read;
///     re-import the file on the other device.
///   - IPTV Favorites (starred channels)
///   - IPTV custom lists (each list with its channels)
///   - Stream badge rulesets (imported badges.json sources)
///
/// Restore intentionally skips remote validation (network) for credentials —
/// the user trusts their own backup, so we write the stored values directly.
/// Search engines and addons still require network on restore.
class BackupRestoreService {
  /// Highest envelope version this app can read. v1 = the plain payload,
  /// v2 = the passphrase-encrypted envelope wrapping a v1 payload.
  static const int currentVersion = 2;

  /// Version stamped on plain payloads. Deliberately still 1: an unencrypted
  /// export must stay restorable on app versions that predate encryption,
  /// and only the v2 envelope needs the higher gate.
  static const int payloadVersion = 1;

  /// Build a backup payload from the current device's configuration.
  ///
  /// With [includeCredentials] false, account secrets are omitted entirely
  /// (debrid keys, PikPak, Trakt, Simkl, MDBList) or blanked in place (WebDAV
  /// passwords, indexer API keys, Xtream usernames/passwords) so a setup can
  /// be shared without handing over accounts. M3U playlist URLs are kept —
  /// the URL *is* the provider config; users who need those protected should
  /// use a passphrase instead.
  static Future<Map<String, dynamic>> buildBackup({
    bool includeCredentials = true,
  }) async {
    final realDebridKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final premiumizeKey = await StorageService.getPremiumizeApiKey();
    final allDebridKey = await StorageService.getAllDebridApiKey();
    final pikpakEmail = await StorageService.getPikPakEmail();
    final pikpakPassword = await StorageService.getPikPakPassword();
    final traktAccess = await StorageService.getTraktAccessToken();
    final traktRefresh = await StorageService.getTraktRefreshToken();
    final traktExpiry = await StorageService.getTraktTokenExpiry();
    final traktUsername = await StorageService.getTraktUsername();
    final simklAccess = await StorageService.getSimklAccessToken();
    final simklUsername = await StorageService.getSimklUsername();
    final mdblistApiKey = await StorageService.getMdblistApiKey();
    final mdblistUsername = await StorageService.getMdblistUsername();
    final mdblistSyncCheckpoint =
        await StorageService.getMdblistSyncCheckpoint();
    final trackingPreferences =
        await StorageService.buildTrackingPreferencesPayload();
    final scrobbleTargets = (trackingPreferences['scrobble_targets'] as List)
        .map((value) => value.toString())
        .toSet();

    await LocalEngineStorage.instance.initialize();
    final engineIds = await LocalEngineStorage.instance.getImportedEngineIds();

    List<String> addonUrls = const [];
    if (includeCredentials) {
      // Omitted from credential-free exports: configured manifest URLs
      // routinely embed debrid API keys in the path (Torrentio/Comet-style
      // configure strings), and there is no reliable way to scrub them.
      try {
        // Retain disabled owned addons, but do not bypass settings redaction
        // for borrowed resources: a use-only grant must not turn into an
        // exported configured URL. Redacted empty URLs are omitted below.
        final addons = await StremioService.instance.getAddons(
          forSettings: true,
        );
        addonUrls = backupAddonManifestUrls(
          addons.map((addon) => addon.manifestUrl),
        );
      } catch (_) {
        throw StateError('Could not read Stremio addons for backup');
      }
    }

    List<Map<String, dynamic>> webDavServers = const [];
    try {
      final servers = await StorageService.getWebDavServers();
      webDavServers = servers.map((s) {
        final json = s.toTransferJson();
        if (!includeCredentials) json['password'] = '';
        return json;
      }).toList();
    } catch (_) {
      throw StateError('Could not read WebDAV servers for backup');
    }

    List<Map<String, dynamic>> indexerManagers = const [];
    if (includeCredentials) {
      // Omitted entirely from credential-free exports: an entry without its
      // API key is rejected by the restorer, so keeping blanked ones would
      // just advertise a category that always fails to import.
      try {
        final configs = await StorageService.getIndexerManagerConfigs();
        indexerManagers = configs.map((c) => c.toTransferJson()).toList();
      } catch (_) {
        throw StateError('Could not read indexer managers for backup');
      }
    }

    List<Map<String, dynamic>> iptvPlaylists = const [];
    List<Map<String, dynamic>> iptvFavorites = const [];
    List<Map<String, dynamic>> iptvLists = const [];
    try {
      iptvPlaylists = await IptvTransferPayload.buildPlaylists();
      if (!includeCredentials) {
        // Xtream providers are dropped whole: every field that could travel
        // (`url`, `epgUrl`) embeds the account, and an entry stripped of its
        // url fails to restore. Plain-M3U providers are kept with their url
        // intact — there the URL IS the config, which the export dialog
        // documents.
        iptvPlaylists.removeWhere(
          (p) => (p['serverUrl'] as String?)?.isNotEmpty == true,
        );
        for (final playlist in iptvPlaylists) {
          playlist.remove('username');
          playlist.remove('password');
        }
      }
      if (includeCredentials) {
        // Favorite/list entries carry per-channel STREAM URLs, which for
        // Xtream providers embed the account password in the path — they
        // cannot be scrubbed without breaking them, so credential-free
        // exports leave the whole category out.
        iptvFavorites = await IptvTransferPayload.buildFavorites();
        iptvLists = await IptvTransferPayload.buildCustomLists();
      }
    } catch (_) {
      throw StateError('Could not read IPTV setup for backup');
    }

    List<Map<String, dynamic>> streamBadges = const [];
    try {
      streamBadges = await StreamBadgesService.instance.exportJson();
    } catch (_) {
      throw StateError('Could not read stream badge rulesets for backup');
    }

    return <String, dynamic>{
      'version': payloadVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'trackingPreferences': trackingPreferences,
      if (includeCredentials) ...{
        if (realDebridKey != null && realDebridKey.isNotEmpty)
          'realDebridApiKey': realDebridKey,
        if (torboxKey != null && torboxKey.isNotEmpty)
          'torboxApiKey': torboxKey,
        if (premiumizeKey != null && premiumizeKey.isNotEmpty)
          'premiumizeApiKey': premiumizeKey,
        if (allDebridKey != null && allDebridKey.isNotEmpty)
          'allDebridApiKey': allDebridKey,
        if (pikpakEmail != null && pikpakEmail.isNotEmpty)
          'pikpak': <String, dynamic>{
            'email': pikpakEmail,
            if (pikpakPassword != null && pikpakPassword.isNotEmpty)
              'password': pikpakPassword,
          },
        if (traktAccess != null &&
            traktAccess.isNotEmpty &&
            traktRefresh != null &&
            traktRefresh.isNotEmpty)
          'trakt': <String, dynamic>{
            'access_token': traktAccess,
            'refresh_token': traktRefresh,
            if (traktExpiry != null) 'expiry_ms': traktExpiry,
            if (traktUsername != null && traktUsername.isNotEmpty)
              'username': traktUsername,
          },
        if (simklAccess != null && simklAccess.isNotEmpty)
          'simkl': <String, dynamic>{
            'access_token': simklAccess,
            if (simklUsername != null && simklUsername.isNotEmpty)
              'username': simklUsername,
          },
        if (mdblistApiKey != null && mdblistApiKey.isNotEmpty)
          'mdblist': <String, dynamic>{
            'api_key': mdblistApiKey,
            if (mdblistUsername != null && mdblistUsername.isNotEmpty)
              'username': mdblistUsername,
            // Retained only as a compatibility field for older Debrify
            // restores. Derive it from the new master; never read the retired
            // preference again after one-time master seeding.
            'sync_catalog_items': scrobbleTargets.contains('mdblist'),
            if (mdblistSyncCheckpoint != null)
              'sync_checkpoint': mdblistSyncCheckpoint,
          },
      },
      if (engineIds.isNotEmpty) 'searchEngineIds': engineIds,
      if (addonUrls.isNotEmpty) 'addonManifestUrls': addonUrls,
      if (webDavServers.isNotEmpty) 'webDavServers': webDavServers,
      if (indexerManagers.isNotEmpty) 'indexerManagers': indexerManagers,
      if (iptvPlaylists.isNotEmpty) 'iptvPlaylists': iptvPlaylists,
      if (iptvFavorites.isNotEmpty) 'iptvFavorites': iptvFavorites,
      if (iptvLists.isNotEmpty) 'iptvLists': iptvLists,
      if (streamBadges.isNotEmpty) 'streamBadges': streamBadges,
    };
  }

  @visibleForTesting
  static List<String> backupAddonManifestUrls(Iterable<String> urls) =>
      <String>{
        for (final url in urls)
          if (url.trim().isNotEmpty) url.trim(),
      }.toList(growable: false);

  /// Summarize what's inside a parsed backup map (for the confirm dialog).
  static BackupSummary summarize(Map<String, dynamic> map) {
    return BackupSummary(
      version: (map['version'] as num?)?.toInt(),
      createdAt: map['createdAt'] as String?,
      hasRealDebrid: (map['realDebridApiKey'] as String?)?.isNotEmpty ?? false,
      hasTorbox: (map['torboxApiKey'] as String?)?.isNotEmpty ?? false,
      hasPremiumize: (map['premiumizeApiKey'] as String?)?.isNotEmpty ?? false,
      hasAllDebrid: (map['allDebridApiKey'] as String?)?.isNotEmpty ?? false,
      hasPikpak:
          (map['pikpak'] is Map) &&
          ((map['pikpak'] as Map)['email'] as String?)?.isNotEmpty == true,
      hasTrakt:
          (map['trakt'] is Map) &&
          ((map['trakt'] as Map)['access_token'] as String?)?.isNotEmpty ==
              true,
      hasSimkl:
          (map['simkl'] is Map) &&
          ((map['simkl'] as Map)['access_token'] as String?)?.isNotEmpty ==
              true,
      hasMdblist:
          (map['mdblist'] is Map) &&
          ((map['mdblist'] as Map)['api_key'] as String?)?.isNotEmpty == true,
      searchEngineCount: (map['searchEngineIds'] as List?)?.length ?? 0,
      addonCount: (map['addonManifestUrls'] as List?)?.length ?? 0,
      webDavServerCount: (map['webDavServers'] as List?)?.length ?? 0,
      indexerManagerCount: (map['indexerManagers'] as List?)?.length ?? 0,
      iptvPlaylistCount: (map['iptvPlaylists'] as List?)?.length ?? 0,
      iptvFavoriteCount: (map['iptvFavorites'] as List?)?.length ?? 0,
      iptvListCount: (map['iptvLists'] as List?)?.length ?? 0,
      iptvListChannelCount: IptvTransferPayload.countListChannels(
        (map['iptvLists'] as List?) ?? const [],
      ),
      streamBadgeSourceCount: (map['streamBadges'] as List?)?.length ?? 0,
    );
  }

  /// Parse a JSON string into a backup map. Throws [FormatException] on
  /// invalid JSON or unrecognized shape.
  static Map<String, dynamic> parse(String jsonContent) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonContent);
    } catch (e) {
      throw const FormatException('File is not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup file is not a JSON object');
    }
    final version = (decoded['version'] as num?)?.toInt();
    if (version == null) {
      throw const FormatException('Missing "version" field');
    }
    if (version > currentVersion) {
      throw FormatException(
        'Backup version $version is newer than this app supports '
        '(max $currentVersion). Update the app and try again.',
      );
    }
    return decoded;
  }

  /// Whether a parsed map is a passphrase-encrypted v2 envelope (whose inner
  /// payload must be recovered with [decryptBackup] before use).
  static bool isEncrypted(Map<String, dynamic> map) => map['encrypted'] == true;

  /// Wrap a plain backup payload in a passphrase-encrypted v2 envelope.
  ///
  /// `createdAt` is duplicated outside the ciphertext so the restore dialog
  /// can show it before asking for the passphrase. Always writes Argon2id;
  /// [kdfParams] exists so tests can use fast parameters.
  static Future<Map<String, dynamic>> encryptBackup(
    Map<String, dynamic> payload,
    String passphrase, {
    @visibleForTesting BackupKdfParams kdfParams = const BackupKdfParams(),
  }) async {
    final salt = _randomBytes(16);
    final key = await Argon2id(
      parallelism: kdfParams.parallelism,
      memory: kdfParams.memory,
      iterations: kdfParams.iterations,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
    );
    return <String, dynamic>{
      'version': 2,
      'encrypted': true,
      if (payload['createdAt'] is String) 'createdAt': payload['createdAt'],
      'kdf': <String, dynamic>{
        'algo': 'argon2id',
        'salt': base64Encode(salt),
        'm': kdfParams.memory,
        't': kdfParams.iterations,
        'p': kdfParams.parallelism,
      },
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(<int>[...box.cipherText, ...box.mac.bytes]),
    };
  }

  /// Recover the inner payload of a v2 envelope.
  ///
  /// Throws [BackupPassphraseException] when the passphrase is wrong (GCM tag
  /// failure) and [FormatException] when the envelope itself is malformed or
  /// uses an unknown KDF. KDF parameters are read FROM the envelope;
  /// `pbkdf2-hmac-sha256` is accepted on import for forward compatibility
  /// even though this app only ever writes `argon2id`.
  static Future<Map<String, dynamic>> decryptBackup(
    Map<String, dynamic> envelope,
    String passphrase,
  ) async {
    final kdf = envelope['kdf'];
    final nonceB64 = envelope['nonce'];
    final ciphertextB64 = envelope['ciphertext'];
    if (kdf is! Map || nonceB64 is! String || ciphertextB64 is! String) {
      throw const FormatException('Encrypted backup is missing fields');
    }
    final List<int> salt;
    final List<int> nonce;
    final List<int> packed;
    try {
      salt = base64Decode(kdf['salt'] as String);
      nonce = base64Decode(nonceB64);
      packed = base64Decode(ciphertextB64);
    } catch (_) {
      throw const FormatException('Encrypted backup is corrupted');
    }
    if (packed.length < 16) {
      throw const FormatException('Encrypted backup is corrupted');
    }

    // The KDF cost parameters come from the FILE — cap them before deriving,
    // or a crafted backup can request gigabytes of Argon2 memory and freeze
    // the app the moment the user enters a passphrase.
    int boundedParam(dynamic value, int fallback, int min, int max) {
      if (value != null && value is! num) {
        throw const FormatException('Encrypted backup is corrupted');
      }
      final parsed = value == null ? fallback : (value as num).toInt();
      if (parsed < min || parsed > max) {
        throw const FormatException(
          'Encrypted backup requests unreasonable KDF cost',
        );
      }
      return parsed;
    }

    if (salt.length < 8 || salt.length > 64) {
      throw const FormatException('Encrypted backup is corrupted');
    }

    final algo = kdf['algo'];
    final SecretKey key;
    if (algo == 'argon2id') {
      final parallelism = boundedParam(kdf['p'], 1, 1, 8);
      final memory = boundedParam(kdf['m'], 19456, 8, 131072); // ≤ 128 MiB
      // Argon2 itself requires memory ≥ 8·parallelism; values passing the
      // independent bounds (e.g. p=8, m=8) would throw an ArgumentError out
      // of the KDF instead of the FormatException the UI handles.
      if (memory < 8 * parallelism) {
        throw const FormatException(
          'Encrypted backup requests unreasonable KDF cost',
        );
      }
      key = await Argon2id(
        parallelism: parallelism,
        memory: memory,
        iterations: boundedParam(kdf['t'], 2, 1, 16),
        hashLength: 32,
      ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
    } else if (algo == 'pbkdf2-hmac-sha256') {
      key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: boundedParam(kdf['iterations'], 600000, 1000, 5000000),
        bits: 256,
      ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
    } else {
      throw FormatException('Unknown backup KDF "$algo"');
    }

    final box = SecretBox(
      packed.sublist(0, packed.length - 16),
      nonce: nonce,
      mac: Mac(packed.sublist(packed.length - 16)),
    );
    final List<int> plaintext;
    try {
      plaintext = await AesGcm.with256bits().decrypt(box, secretKey: key);
    } catch (_) {
      throw const BackupPassphraseException();
    }
    final dynamic inner;
    try {
      inner = jsonDecode(utf8.decode(plaintext));
    } catch (_) {
      throw const FormatException('Encrypted backup is corrupted');
    }
    if (inner is! Map<String, dynamic>) {
      throw const FormatException('Encrypted backup is corrupted');
    }
    // The decrypted payload bypasses parse(), so it needs the same version
    // gate — an envelope wrapping a future (or version-less) payload must
    // fail here, exactly as its plaintext twin would.
    final innerVersion = (inner['version'] as num?)?.toInt();
    if (innerVersion == null) {
      throw const FormatException('Missing "version" field');
    }
    if (innerVersion > currentVersion) {
      throw FormatException(
        'Backup version $innerVersion is newer than this app supports '
        '(max $currentVersion). Update the app and try again.',
      );
    }
    return inner;
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  /// Apply a parsed backup. Returns a [RestoreReport] summarizing what was
  /// applied and what failed. Network is only required for search engines
  /// and addons; credential restores are local writes.
  static Future<RestoreReport> applyBackup(
    Map<String, dynamic> map, {
    BackupSelection selection = const BackupSelection.all(),
    bool refreshEngineRuntime = true,
  }) async {
    final report = RestoreReport();

    if (selection.realDebrid) {
      final key = map['realDebridApiKey'] as String?;
      if (key != null && key.isNotEmpty) {
        try {
          await StorageService.saveApiKey(key);
          await StorageService.setRealDebridIntegrationEnabled(true);
          report.realDebrid = true;
        } catch (_) {
          report.errors.add('Real-Debrid: restore failed');
        }
      }
    }

    if (selection.torbox) {
      final key = map['torboxApiKey'] as String?;
      if (key != null && key.isNotEmpty) {
        try {
          await StorageService.saveTorboxApiKey(key);
          await StorageService.setTorboxIntegrationEnabled(true);
          report.torbox = true;
        } catch (_) {
          report.errors.add('Torbox: restore failed');
        }
      }
    }

    if (selection.premiumize) {
      final key = map['premiumizeApiKey'] as String?;
      if (key != null && key.isNotEmpty) {
        try {
          await StorageService.savePremiumizeApiKey(key);
          await StorageService.setPremiumizeIntegrationEnabled(true);
          report.premiumize = true;
        } catch (_) {
          report.errors.add('Premiumize: restore failed');
        }
      }
    }

    if (selection.allDebrid) {
      final key = map['allDebridApiKey'] as String?;
      if (key != null && key.isNotEmpty) {
        try {
          await StorageService.saveAllDebridApiKey(key);
          await StorageService.setAllDebridIntegrationEnabled(true);
          report.allDebrid = true;
        } catch (_) {
          report.errors.add('AllDebrid: restore failed');
        }
      }
    }

    if (selection.pikpak) {
      final pp = map['pikpak'];
      if (pp is Map) {
        final email = pp['email'] as String?;
        final password = pp['password'] as String?;
        if (email != null && email.isNotEmpty) {
          try {
            await StorageService.setPikPakEmail(email);
            if (password != null && password.isNotEmpty) {
              await StorageService.setPikPakPassword(password);
            }
            await StorageService.setPikPakEnabled(true);
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
                report.pikpak = loggedIn;
                if (!loggedIn) {
                  report.pikpakLoginFailed = true;
                }
              } catch (_) {
                report.pikpakLoginFailed = true;
                debugPrint('BackupRestoreService: PikPak login failed');
              }
            } else {
              // No password in backup — credentials saved but can't log in.
              report.pikpak = true;
              report.pikpakLoginFailed = true;
            }
          } catch (_) {
            report.errors.add('PikPak: restore failed');
          }
        }
      }
    }

    if (selection.trakt) {
      final t = map['trakt'];
      if (t is Map) {
        final access = t['access_token'] as String?;
        final refresh = t['refresh_token'] as String?;
        if (access != null &&
            access.isNotEmpty &&
            refresh != null &&
            refresh.isNotEmpty) {
          try {
            await StorageService.setTraktAccessToken(access);
            await StorageService.setTraktRefreshToken(refresh);
            final expiry = (t['expiry_ms'] as num?)?.toInt();
            if (expiry != null) {
              await StorageService.setTraktTokenExpiry(expiry);
            }
            final username = t['username'] as String?;
            if (username != null && username.isNotEmpty) {
              await StorageService.setTraktUsername(username);
            }
            // Match interactive connect: a freshly imported Trakt session
            // starts with catalog scrobbling on.
            await StorageService.setTraktSyncCatalogItems(true);
            report.trakt = true;
          } catch (_) {
            report.errors.add('Trakt: restore failed');
          }
        }
      }
    }

    if (selection.simkl) {
      final s = map['simkl'];
      if (s is Map) {
        final access = s['access_token'] as String?;
        if (access != null && access.isNotEmpty) {
          try {
            await StorageService.setSimklAccessToken(access);
            final username = s['username'] as String?;
            if (username != null && username.isNotEmpty) {
              await StorageService.setSimklUsername(username);
            }
            // Match interactive connect: a freshly imported Simkl session
            // starts with catalog scrobbling on.
            await StorageService.setSimklSyncCatalogItems(true);
            report.simkl = true;
          } catch (_) {
            report.errors.add('Simkl: restore failed');
          }
        }
      }
    }

    if (selection.mdblist) {
      final m = map['mdblist'];
      if (m is Map) {
        final apiKey = m['api_key'] as String?;
        if (apiKey != null && apiKey.isNotEmpty) {
          try {
            await StorageService.saveMdblistApiKey(apiKey);
            final username = m['username'] as String?;
            await StorageService.setMdblistUsername(username);
            await StorageService.setMdblistSyncCatalogItems(
              m['sync_catalog_items'] as bool? ?? true,
            );
            final checkpoint = m['sync_checkpoint'];
            await StorageService.setMdblistSyncCheckpoint(
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
            report.mdblist = true;
          } catch (_) {
            report.errors.add('MDBList: restore failed');
          }
        }
      }
    }

    if (selection.searchEngines) {
      final ids = (map['searchEngineIds'] as List?)?.cast<String>() ?? const [];
      if (ids.isNotEmpty) {
        await _restoreSearchEngines(
          ids,
          report,
          refreshRuntime: refreshEngineRuntime,
        );
      }
    }

    if (selection.addons) {
      final urls =
          (map['addonManifestUrls'] as List?)?.cast<String>() ?? const [];
      if (urls.isNotEmpty) {
        await _restoreAddons(urls, report);
      }
    }

    if (selection.webDav) {
      final list = map['webDavServers'];
      if (list is List && list.isNotEmpty) {
        await _restoreWebDavServers(list, report);
      }
    }

    if (selection.indexerManagers) {
      final list = map['indexerManagers'];
      if (list is List && list.isNotEmpty) {
        await _restoreIndexerManagers(list, report);
      }
    }

    // Providers first: Favorites and list memberships name the playlist they
    // came from, so restoring them before their provider exists would leave
    // channels pointing at nothing.
    if (selection.iptvPlaylists) {
      final list = map['iptvPlaylists'];
      if (list is List && list.isNotEmpty) {
        final counts = await IptvTransferPayload.applyPlaylists(list);
        report.iptvPlaylistsImported = counts.imported;
        report.iptvPlaylistsAlreadyPresent = counts.alreadyPresent;
        report.iptvPlaylistsFailed = counts.failed;
        if (counts.error != null) {
          report.errors.add('IPTV providers: ${counts.error}');
        }
      }
    }

    if (selection.iptvFavorites) {
      final list = map['iptvFavorites'];
      if (list is List && list.isNotEmpty) {
        final counts = await IptvTransferPayload.applyFavorites(list);
        report.iptvFavoritesImported = counts.channelsImported;
        report.iptvFavoritesAlreadyPresent = counts.channelsAlreadyPresent;
        report.iptvFavoritesFailed = counts.failed;
        if (counts.error != null) {
          report.errors.add('IPTV favorites: ${counts.error}');
        }
      }
    }

    if (selection.iptvLists) {
      final list = map['iptvLists'];
      if (list is List && list.isNotEmpty) {
        final counts = await IptvTransferPayload.applyCustomLists(list);
        report.iptvListsCreated = counts.imported;
        report.iptvListsMerged = counts.alreadyPresent;
        report.iptvListChannelsImported = counts.channelsImported;
        report.iptvListChannelsAlreadyPresent = counts.channelsAlreadyPresent;
        report.iptvListsFailed = counts.failed;
        if (counts.error != null) {
          report.errors.add('IPTV lists: ${counts.error}');
        }
      }
    }

    if (selection.streamBadges) {
      final list = map['streamBadges'];
      if (list is List && list.isNotEmpty) {
        try {
          final counts = await StreamBadgesService.instance.applyBackup(list);
          report.streamBadgeSourcesImported = counts.imported;
          report.streamBadgeSourcesAlreadyPresent = counts.alreadyPresent;
          report.streamBadgeSourcesFailed = counts.failed;
        } catch (_) {
          report.errors.add('Stream badges: restore failed');
        }
      }
    }

    final trackingPreferences = map['trackingPreferences'];
    if (selection.trackingPreferences && trackingPreferences is Map) {
      try {
        await StorageService.applyTrackingPreferencesPayload(
          trackingPreferences,
        );
      } catch (_) {
        report.errors.add('Tracking preferences: restore failed');
      }
    } else if (trackingPreferences == null &&
        (report.trakt || report.simkl || report.mdblist)) {
      // Old backup: it restored the legacy per-tracker sync-catalog switches
      // but carries no tracking payload. The scrobble masters were already
      // seeded on this install's first policy read, so re-adopt the
      // just-restored legacy values (absent-key rule: Trakt/Simkl default ON,
      // MDBList follows its restored switch).
      await StorageService.reseedTrackingScrobbleTargetsFromLegacy();
    }

    return report;
  }

  /// Merge restored WebDAV servers into the existing list. We de-dupe by
  /// normalized base URL — restoring the same backup twice doesn't duplicate
  /// entries, but a different server at a different URL is added.
  static Future<void> _restoreWebDavServers(
    List<dynamic> entries,
    RestoreReport report,
  ) async {
    try {
      final existing = await StorageService.getWebDavServers();
      final existingUrls = <String>{
        for (final s in existing) _normalizeUrl(s.baseUrl),
      };
      final merged = List<WebDavConfig>.from(existing);
      for (final raw in entries) {
        if (raw is! Map) {
          report.webDavServersFailed++;
          continue;
        }
        try {
          final config = WebDavConfig.fromTransferJson(
            Map<String, dynamic>.from(raw),
          );
          if (config.baseUrl.trim().isEmpty) {
            report.webDavServersFailed++;
            continue;
          }
          final key = _normalizeUrl(config.baseUrl);
          if (existingUrls.contains(key)) {
            report.webDavServersAlreadyPresent++;
            continue;
          }
          merged.add(config);
          existingUrls.add(key);
          report.webDavServersImported++;
        } catch (_) {
          debugPrint('BackupRestoreService: WebDAV entry failed');
          report.webDavServersFailed++;
        }
      }
      if (report.webDavServersImported > 0) {
        await StorageService.saveWebDavServers(merged);
        // setWebDavEnabled is handled inside saveWebDavServers.
      }
    } catch (_) {
      report.errors.add('WebDAV: restore failed');
    }
  }

  /// Merge restored indexer manager configs into the existing list. De-duped
  /// by (type, normalized baseUrl) so re-importing the same backup is a
  /// no-op, but a different host or different type is added.
  static Future<void> _restoreIndexerManagers(
    List<dynamic> entries,
    RestoreReport report,
  ) async {
    try {
      final existing = await StorageService.getIndexerManagerConfigs();
      String fingerprint(IndexerManagerConfig c) =>
          '${c.type.value}|${_normalizeUrl(c.baseUrl)}';
      final existingKeys = <String>{for (final c in existing) fingerprint(c)};
      final merged = List<IndexerManagerConfig>.from(existing);
      for (final raw in entries) {
        if (raw is! Map) {
          report.indexerManagersFailed++;
          continue;
        }
        try {
          final config = IndexerManagerConfig.fromTransferJson(
            Map<String, dynamic>.from(raw),
          );
          if (config.baseUrl.trim().isEmpty || config.apiKey.trim().isEmpty) {
            report.indexerManagersFailed++;
            continue;
          }
          final key = fingerprint(config);
          if (existingKeys.contains(key)) {
            report.indexerManagersAlreadyPresent++;
            continue;
          }
          merged.add(config);
          existingKeys.add(key);
          report.indexerManagersImported++;
        } catch (_) {
          debugPrint('BackupRestoreService: indexer manager entry failed');
          report.indexerManagersFailed++;
        }
      }
      if (report.indexerManagersImported > 0) {
        await StorageService.setIndexerManagerConfigs(merged);
      }
    } catch (_) {
      report.errors.add('Indexer managers: restore failed');
    }
  }

  static String _normalizeUrl(String url) {
    return url.trim().toLowerCase().replaceFirst(RegExp(r'/+$'), '');
  }

  static Future<void> _restoreSearchEngines(
    List<String> engineIds,
    RestoreReport report, {
    required bool refreshRuntime,
  }) async {
    try {
      final remoteManager = RemoteEngineManager();
      final localStorage = LocalEngineStorage.instance;
      await localStorage.initialize();

      final available = await remoteManager.fetchAvailableEngines();
      for (final id in engineIds) {
        try {
          if (await localStorage.isEngineImported(id)) {
            report.searchEnginesAlreadyPresent++;
            continue;
          }
          final info = available.where((e) => e.id == id).firstOrNull;
          if (info == null) {
            report.searchEnginesFailed++;
            continue;
          }
          final yaml = await remoteManager.downloadEngineYaml(info.fileName);
          if (yaml == null) {
            report.searchEnginesFailed++;
            continue;
          }
          await localStorage.saveEngine(
            engineId: id,
            fileName: info.fileName,
            yamlContent: yaml,
            displayName: info.displayName,
            icon: info.icon,
          );
          report.searchEnginesImported++;
        } catch (_) {
          debugPrint('BackupRestoreService: engine import failed');
          report.searchEnginesFailed++;
        }
      }

      // Refresh the in-memory engine registry so newly-imported engines are
      // visible to keyword search without an app restart. Skip when nothing
      // was actually written to disk — the registry already matches.
      if (refreshRuntime && report.searchEnginesImported > 0) {
        ConfigLoader().clearCache();
        await EngineRegistry.instance.reload();
      }
    } catch (_) {
      report.errors.add('Search engines: restore failed');
    }
  }

  static Future<void> _restoreAddons(
    List<String> urls,
    RestoreReport report,
  ) async {
    try {
      // Avoid importing duplicates of disabled owned addons or executable
      // shared addons whose settings representation redacts its URL.
      final existing = await StremioService.instance.getAddonsForManagement();
      final existingUrls = existing.map((a) => a.manifestUrl).toSet();
      for (final url in urls) {
        if (existingUrls.contains(url)) {
          report.addonsAlreadyPresent++;
          continue;
        }
        try {
          await StremioService.instance.addAddon(url);
          report.addonsImported++;
        } catch (_) {
          debugPrint('BackupRestoreService: addon import failed');
          report.addonsFailed++;
        }
      }
    } catch (_) {
      report.errors.add('Addons: restore failed');
    }
  }
}

/// Snapshot of what's in a backup file — used to populate the restore dialog.
class BackupSummary {
  final int? version;
  final String? createdAt;
  final bool hasRealDebrid;
  final bool hasTorbox;
  final bool hasPremiumize;
  final bool hasAllDebrid;
  final bool hasPikpak;
  final bool hasTrakt;
  final bool hasSimkl;
  final bool hasMdblist;
  final int searchEngineCount;
  final int addonCount;
  final int webDavServerCount;
  final int indexerManagerCount;
  final int iptvPlaylistCount;
  final int iptvFavoriteCount;
  final int iptvListCount;
  final int iptvListChannelCount;
  final int streamBadgeSourceCount;

  BackupSummary({
    required this.version,
    required this.createdAt,
    required this.hasRealDebrid,
    required this.hasTorbox,
    required this.hasPremiumize,
    required this.hasAllDebrid,
    required this.hasPikpak,
    required this.hasTrakt,
    required this.hasSimkl,
    required this.hasMdblist,
    required this.searchEngineCount,
    required this.addonCount,
    required this.webDavServerCount,
    required this.indexerManagerCount,
    this.iptvPlaylistCount = 0,
    this.iptvFavoriteCount = 0,
    this.iptvListCount = 0,
    this.iptvListChannelCount = 0,
    this.streamBadgeSourceCount = 0,
  });

  bool get isEmpty =>
      !hasRealDebrid &&
      !hasTorbox &&
      !hasPremiumize &&
      !hasAllDebrid &&
      !hasPikpak &&
      !hasTrakt &&
      !hasSimkl &&
      !hasMdblist &&
      searchEngineCount == 0 &&
      addonCount == 0 &&
      webDavServerCount == 0 &&
      indexerManagerCount == 0 &&
      iptvPlaylistCount == 0 &&
      iptvFavoriteCount == 0 &&
      iptvListCount == 0 &&
      streamBadgeSourceCount == 0;
}

/// Which categories to include when restoring.
class BackupSelection {
  final bool realDebrid;
  final bool torbox;
  final bool premiumize;
  final bool allDebrid;
  final bool pikpak;
  final bool trakt;
  final bool simkl;
  final bool mdblist;
  final bool searchEngines;
  final bool addons;
  final bool webDav;
  final bool indexerManagers;
  final bool iptvPlaylists;
  final bool iptvFavorites;
  final bool iptvLists;
  final bool streamBadges;
  final bool trackingPreferences;

  const BackupSelection({
    required this.realDebrid,
    required this.torbox,
    required this.premiumize,
    required this.allDebrid,
    required this.pikpak,
    required this.trakt,
    required this.simkl,
    this.mdblist = true,
    required this.searchEngines,
    required this.addons,
    required this.webDav,
    required this.indexerManagers,
    this.iptvPlaylists = true,
    this.iptvFavorites = true,
    this.iptvLists = true,
    this.streamBadges = true,
    this.trackingPreferences = false,
  });

  const BackupSelection.all()
    : realDebrid = true,
      torbox = true,
      premiumize = true,
      allDebrid = true,
      pikpak = true,
      trakt = true,
      simkl = true,
      mdblist = true,
      searchEngines = true,
      addons = true,
      webDav = true,
      indexerManagers = true,
      iptvPlaylists = true,
      iptvFavorites = true,
      iptvLists = true,
      streamBadges = true,
      trackingPreferences = true;

  BackupSelection copyWith({
    bool? realDebrid,
    bool? torbox,
    bool? premiumize,
    bool? allDebrid,
    bool? pikpak,
    bool? trakt,
    bool? simkl,
    bool? mdblist,
    bool? searchEngines,
    bool? addons,
    bool? webDav,
    bool? indexerManagers,
    bool? iptvPlaylists,
    bool? iptvFavorites,
    bool? iptvLists,
    bool? streamBadges,
    bool? trackingPreferences,
  }) {
    return BackupSelection(
      realDebrid: realDebrid ?? this.realDebrid,
      torbox: torbox ?? this.torbox,
      premiumize: premiumize ?? this.premiumize,
      allDebrid: allDebrid ?? this.allDebrid,
      pikpak: pikpak ?? this.pikpak,
      trakt: trakt ?? this.trakt,
      simkl: simkl ?? this.simkl,
      mdblist: mdblist ?? this.mdblist,
      searchEngines: searchEngines ?? this.searchEngines,
      addons: addons ?? this.addons,
      webDav: webDav ?? this.webDav,
      indexerManagers: indexerManagers ?? this.indexerManagers,
      iptvPlaylists: iptvPlaylists ?? this.iptvPlaylists,
      iptvFavorites: iptvFavorites ?? this.iptvFavorites,
      iptvLists: iptvLists ?? this.iptvLists,
      streamBadges: streamBadges ?? this.streamBadges,
      trackingPreferences: trackingPreferences ?? this.trackingPreferences,
    );
  }
}

/// Result of a restore operation — surfaced to the user via snackbars / dialog.
class RestoreReport {
  bool realDebrid = false;
  bool torbox = false;
  bool premiumize = false;
  bool allDebrid = false;
  bool pikpak = false;
  // True if PikPak credentials were saved but logging in failed (offline,
  // wrong password, etc.). Saved credentials remain usable from settings.
  bool pikpakLoginFailed = false;
  bool trakt = false;
  bool simkl = false;
  bool mdblist = false;
  int searchEnginesImported = 0;
  int searchEnginesAlreadyPresent = 0;
  int searchEnginesFailed = 0;
  int addonsImported = 0;
  int addonsAlreadyPresent = 0;
  int addonsFailed = 0;
  int webDavServersImported = 0;
  int webDavServersAlreadyPresent = 0;
  int webDavServersFailed = 0;
  int indexerManagersImported = 0;
  int indexerManagersAlreadyPresent = 0;
  int indexerManagersFailed = 0;
  int iptvPlaylistsImported = 0;
  int iptvPlaylistsAlreadyPresent = 0;
  int iptvPlaylistsFailed = 0;
  int iptvFavoritesImported = 0;
  int iptvFavoritesAlreadyPresent = 0;
  int iptvFavoritesFailed = 0;
  int iptvListsCreated = 0;
  // Lists that already existed by name and were topped up rather than added.
  int iptvListsMerged = 0;
  int iptvListChannelsImported = 0;
  int iptvListChannelsAlreadyPresent = 0;
  int iptvListsFailed = 0;
  int streamBadgeSourcesImported = 0;
  int streamBadgeSourcesAlreadyPresent = 0;
  int streamBadgeSourcesFailed = 0;
  final List<String> errors = [];

  int get totalSuccess =>
      (realDebrid ? 1 : 0) +
      (torbox ? 1 : 0) +
      (premiumize ? 1 : 0) +
      (allDebrid ? 1 : 0) +
      (pikpak ? 1 : 0) +
      (trakt ? 1 : 0) +
      (simkl ? 1 : 0) +
      (mdblist ? 1 : 0) +
      searchEnginesImported +
      addonsImported +
      webDavServersImported +
      indexerManagersImported +
      iptvPlaylistsImported +
      iptvFavoritesImported +
      iptvListsCreated +
      iptvListChannelsImported +
      streamBadgeSourcesImported;

  int get totalFailed =>
      searchEnginesFailed +
      addonsFailed +
      webDavServersFailed +
      indexerManagersFailed +
      iptvPlaylistsFailed +
      iptvFavoritesFailed +
      iptvListsFailed +
      streamBadgeSourcesFailed +
      errors.length +
      (pikpakLoginFailed ? 1 : 0);

  bool get hasAnyFailure => totalFailed > 0;
}

/// Wrong passphrase for an encrypted backup (GCM authentication failed).
/// Distinct from [FormatException] so the import UI can re-prompt instead of
/// aborting.
class BackupPassphraseException implements Exception {
  const BackupPassphraseException();

  @override
  String toString() => 'Wrong passphrase';
}

/// Argon2id cost parameters for [BackupRestoreService.encryptBackup].
/// Defaults are the OWASP minimum recommendation (19 MiB, t=2, p=1) — heavy
/// enough to matter, light enough for TV hardware on a user-initiated action.
class BackupKdfParams {
  /// Memory in 1 KiB blocks.
  final int memory;
  final int iterations;
  final int parallelism;

  const BackupKdfParams({
    this.memory = 19456,
    this.iterations = 2,
    this.parallelism = 1,
  });
}
