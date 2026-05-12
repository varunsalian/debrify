import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'engine/local_engine_storage.dart';
import 'engine/remote_engine_manager.dart';
import 'pikpak_api_service.dart';
import 'storage_service.dart';
import 'stremio_service.dart';

/// Service for creating and applying configuration backups.
///
/// The backup payload mirrors what the Remote feature's "Transfer Everything"
/// flow sends over UDP, but assembled into a single JSON document suitable
/// for writing to a file. Categories covered:
///   - Real-Debrid API key
///   - Torbox API key
///   - PikPak credentials (email + password)
///   - Trakt session (access, refresh, expiry, username)
///   - Search engine IDs (restore re-downloads YAML from the remote registry)
///   - Stremio addon manifest URLs (restore re-fetches manifests)
///
/// Restore intentionally skips remote validation (network) for credentials —
/// the user trusts their own backup, so we write the stored values directly.
/// Search engines and addons still require network on restore.
class BackupRestoreService {
  static const int currentVersion = 1;

  /// Build a backup payload from the current device's configuration.
  static Future<Map<String, dynamic>> buildBackup() async {
    final realDebridKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final pikpakEmail = await StorageService.getPikPakEmail();
    final pikpakPassword = await StorageService.getPikPakPassword();
    final traktAccess = await StorageService.getTraktAccessToken();
    final traktRefresh = await StorageService.getTraktRefreshToken();
    final traktExpiry = await StorageService.getTraktTokenExpiry();
    final traktUsername = await StorageService.getTraktUsername();

    await LocalEngineStorage.instance.initialize();
    final engineIds = await LocalEngineStorage.instance.getImportedEngineIds();

    List<String> addonUrls = const [];
    try {
      final addons = await StremioService.instance.getAddons();
      addonUrls = addons.map((a) => a.manifestUrl).toList();
    } catch (e) {
      debugPrint('BackupRestoreService: Failed to read addons: $e');
    }

    return <String, dynamic>{
      'version': currentVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      if (realDebridKey != null && realDebridKey.isNotEmpty)
        'realDebridApiKey': realDebridKey,
      if (torboxKey != null && torboxKey.isNotEmpty) 'torboxApiKey': torboxKey,
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
      if (engineIds.isNotEmpty) 'searchEngineIds': engineIds,
      if (addonUrls.isNotEmpty) 'addonManifestUrls': addonUrls,
    };
  }

  /// Summarize what's inside a parsed backup map (for the confirm dialog).
  static BackupSummary summarize(Map<String, dynamic> map) {
    return BackupSummary(
      version: (map['version'] as num?)?.toInt(),
      createdAt: map['createdAt'] as String?,
      hasRealDebrid:
          (map['realDebridApiKey'] as String?)?.isNotEmpty ?? false,
      hasTorbox: (map['torboxApiKey'] as String?)?.isNotEmpty ?? false,
      hasPikpak: (map['pikpak'] is Map) &&
          ((map['pikpak'] as Map)['email'] as String?)?.isNotEmpty == true,
      hasTrakt: (map['trakt'] is Map) &&
          ((map['trakt'] as Map)['access_token'] as String?)?.isNotEmpty ==
              true,
      searchEngineCount:
          (map['searchEngineIds'] as List?)?.length ?? 0,
      addonCount: (map['addonManifestUrls'] as List?)?.length ?? 0,
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

  /// Apply a parsed backup. Returns a [RestoreReport] summarizing what was
  /// applied and what failed. Network is only required for search engines
  /// and addons; credential restores are local writes.
  static Future<RestoreReport> applyBackup(
    Map<String, dynamic> map, {
    BackupSelection selection = const BackupSelection.all(),
  }) async {
    final report = RestoreReport();

    if (selection.realDebrid) {
      final key = map['realDebridApiKey'] as String?;
      if (key != null && key.isNotEmpty) {
        try {
          await StorageService.saveApiKey(key);
          await StorageService.setRealDebridIntegrationEnabled(true);
          report.realDebrid = true;
        } catch (e) {
          report.errors.add('Real-Debrid: $e');
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
        } catch (e) {
          report.errors.add('Torbox: $e');
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
                final loggedIn =
                    await PikPakApiService.instance.login(email, password);
                report.pikpak = loggedIn;
                if (!loggedIn) {
                  report.pikpakLoginFailed = true;
                }
              } catch (e) {
                report.pikpakLoginFailed = true;
                debugPrint('BackupRestoreService: PikPak login failed: $e');
              }
            } else {
              // No password in backup — credentials saved but can't log in.
              report.pikpak = true;
              report.pikpakLoginFailed = true;
            }
          } catch (e) {
            report.errors.add('PikPak: $e');
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
            report.trakt = true;
          } catch (e) {
            report.errors.add('Trakt: $e');
          }
        }
      }
    }

    if (selection.searchEngines) {
      final ids = (map['searchEngineIds'] as List?)?.cast<String>() ?? const [];
      if (ids.isNotEmpty) {
        await _restoreSearchEngines(ids, report);
      }
    }

    if (selection.addons) {
      final urls =
          (map['addonManifestUrls'] as List?)?.cast<String>() ?? const [];
      if (urls.isNotEmpty) {
        await _restoreAddons(urls, report);
      }
    }

    return report;
  }

  static Future<void> _restoreSearchEngines(
    List<String> engineIds,
    RestoreReport report,
  ) async {
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
        } catch (e) {
          debugPrint('BackupRestoreService: engine $id failed: $e');
          report.searchEnginesFailed++;
        }
      }
    } catch (e) {
      report.errors.add('Search engines: $e');
    }
  }

  static Future<void> _restoreAddons(
    List<String> urls,
    RestoreReport report,
  ) async {
    try {
      final existing = await StremioService.instance.getAddons();
      final existingUrls = existing.map((a) => a.manifestUrl).toSet();
      for (final url in urls) {
        if (existingUrls.contains(url)) {
          report.addonsAlreadyPresent++;
          continue;
        }
        try {
          await StremioService.instance.addAddon(url);
          report.addonsImported++;
        } catch (e) {
          debugPrint('BackupRestoreService: addon $url failed: $e');
          report.addonsFailed++;
        }
      }
    } catch (e) {
      report.errors.add('Addons: $e');
    }
  }
}

/// Snapshot of what's in a backup file — used to populate the restore dialog.
class BackupSummary {
  final int? version;
  final String? createdAt;
  final bool hasRealDebrid;
  final bool hasTorbox;
  final bool hasPikpak;
  final bool hasTrakt;
  final int searchEngineCount;
  final int addonCount;

  BackupSummary({
    required this.version,
    required this.createdAt,
    required this.hasRealDebrid,
    required this.hasTorbox,
    required this.hasPikpak,
    required this.hasTrakt,
    required this.searchEngineCount,
    required this.addonCount,
  });

  bool get isEmpty =>
      !hasRealDebrid &&
      !hasTorbox &&
      !hasPikpak &&
      !hasTrakt &&
      searchEngineCount == 0 &&
      addonCount == 0;
}

/// Which categories to include when restoring.
class BackupSelection {
  final bool realDebrid;
  final bool torbox;
  final bool pikpak;
  final bool trakt;
  final bool searchEngines;
  final bool addons;

  const BackupSelection({
    required this.realDebrid,
    required this.torbox,
    required this.pikpak,
    required this.trakt,
    required this.searchEngines,
    required this.addons,
  });

  const BackupSelection.all()
      : realDebrid = true,
        torbox = true,
        pikpak = true,
        trakt = true,
        searchEngines = true,
        addons = true;

  BackupSelection copyWith({
    bool? realDebrid,
    bool? torbox,
    bool? pikpak,
    bool? trakt,
    bool? searchEngines,
    bool? addons,
  }) {
    return BackupSelection(
      realDebrid: realDebrid ?? this.realDebrid,
      torbox: torbox ?? this.torbox,
      pikpak: pikpak ?? this.pikpak,
      trakt: trakt ?? this.trakt,
      searchEngines: searchEngines ?? this.searchEngines,
      addons: addons ?? this.addons,
    );
  }
}

/// Result of a restore operation — surfaced to the user via snackbars / dialog.
class RestoreReport {
  bool realDebrid = false;
  bool torbox = false;
  bool pikpak = false;
  // True if PikPak credentials were saved but logging in failed (offline,
  // wrong password, etc.). Saved credentials remain usable from settings.
  bool pikpakLoginFailed = false;
  bool trakt = false;
  int searchEnginesImported = 0;
  int searchEnginesAlreadyPresent = 0;
  int searchEnginesFailed = 0;
  int addonsImported = 0;
  int addonsAlreadyPresent = 0;
  int addonsFailed = 0;
  final List<String> errors = [];

  int get totalSuccess =>
      (realDebrid ? 1 : 0) +
      (torbox ? 1 : 0) +
      (pikpak ? 1 : 0) +
      (trakt ? 1 : 0) +
      searchEnginesImported +
      addonsImported;

  int get totalFailed =>
      searchEnginesFailed + addonsFailed + errors.length +
      (pikpakLoginFailed ? 1 : 0);

  bool get hasAnyFailure => totalFailed > 0;
}
