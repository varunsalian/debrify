import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/tv_hero_artwork_quality.dart';
import 'package:debrify/models/tv_render_quality.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/screens/settings/settings_summary_reads.dart';
import 'package:debrify/services/account_service.dart';
import 'package:debrify/services/alldebrid_account_service.dart';
import 'package:debrify/services/android_native_downloader.dart';
import 'package:debrify/services/diagnostic_log.dart';
import 'package:debrify/services/media_server_service.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/premiumize_account_service.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/services/storage/detail_page_storage.dart';
import 'package:debrify/services/storage/device_storage.dart';
import 'package:debrify/services/storage/discover_storage.dart';
import 'package:debrify/services/storage/home_appearance_storage.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/services/storage/launch_ident_storage.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/player_appearance_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/sidebar_storage.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/services/storage/theme_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/storage/torrent_provider_storage.dart';
import 'package:debrify/services/storage/trakt_storage.dart';
import 'package:debrify/services/storage/tv_display_storage.dart';
import 'package:debrify/services/storage/webdav_server_storage.dart';
import 'package:debrify/services/storage/webdav_storage.dart';
import 'package:debrify/services/torbox_account_service.dart';
import 'package:debrify/utils/app_version_info.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../application/settings_pending_credentials.dart';
import 'settings_summaries.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsSummaryLoader {
  SettingsSummaryLoader(this._summaries, this._deps);
  final SettingsSummaries _summaries;
  final ({
    void Function(dynamic allDebridUser) applyAllDebridUserInfo,
    void Function(dynamic premiumizeUser) applyPremiumizeUserInfo,
    void Function(dynamic user) applyRdUserInfo,
    void Function(dynamic torboxUser) applyTorboxUserInfo,
    Future<Set<ConnectionResourceType>> Function() pendingCredentialTypes,
    Future<bool> Function() activeProfileMayExportDiagnostics,
    bool Function() mounted,
    StateSetter setState,
    Map<String, Future<Object?> Function()> Function() summaryReadOverrides,
  })
  _deps;

  Future<void> loadSummariesForCurrentProfile() async {
    // Phase 1: Load cached/local state instantly (no network)
    final startingScope = ProfileRuntime.scope.value;
    _summaries.summaryLoadFailed = false;
    final summaries = SettingsSummaryReads(
      overrides: _deps.summaryReadOverrides(),
      onFailure: (label, error) {
        if (_deps.mounted() && ProfileRuntime.scope.value == startingScope) {
          _summaries.summaryFailures = {..._summaries.summaryFailures, label};
          if (error is ResourceAuthorizationException) {
            _summaries.summaryUnavailable = {
              ..._summaries.summaryUnavailable,
              label,
            };
          }
        }
        DiagnosticLog.instance.recordEvent(
          source: 'app',
          event: 'settings_summary_read_failed',
          fields: <String, Object?>{
            'item': DiagnosticLabel(label),
            // Exception messages can contain server URLs or credentials.
            'errorType': DiagnosticLabel(error.runtimeType.toString()),
            if (error is ResourceAuthorizationException)
              'authorizationReason': DiagnosticLabel(
                const {
                      'Connection authority is missing',
                      'Connection authority changed',
                      'Resource is unavailable',
                      'Profile feature is disabled',
                      'Resource permission denied',
                      'Profile session is locked',
                      'Profile authorization session has ended',
                      'Profile authorization has changed',
                      'Profile storage is in maintenance mode',
                    }.contains(error.message)
                    ? error.message
                    : 'other',
              ),
          },
        );
      },
    );
    final results = await Future.wait<Object?>([
      summaries.read(
        'Real Debrid',
        () => RealDebridStorage.hasRealDebridCredential(),
        false,
      ),
      summaries.read(
        'Torbox',
        () => TorboxStorage.hasTorboxCredential(),
        false,
      ),
      summaries.read(
        'PikPak',
        () => PikPakApiService.instance.isAuthenticated(),
        false,
      ),
      summaries.read('WebDAV', () => WebdavStorage.getWebDavEnabled(), false),
      summaries.read(
        'WebDAV',
        () => WebdavServerStorage.getWebDavServers(forSettings: true),
        <WebDavConfig>[],
      ),
      summaries.read('Trakt', () => TraktStorage.hasTraktCredential(), false),
      summaries.read('Trakt', () => TraktStorage.getTraktTokenExpiry(), null),
      summaries.read('Trakt', () => TraktStorage.getTraktUsername(), null),
      summaries.read(
        'App version',
        () => AppVersionInfo.get(),
        PackageInfo(
          appName: '',
          packageName: '',
          version: 'Unavailable',
          buildNumber: '',
        ),
      ),
      summaries.read(
        'TV detection',
        () => AndroidNativeDownloader.isTelevision(),
        false,
      ),
      summaries.read(
        'Update checks',
        () => DeviceStorage.getUpdateAutoCheckEnabled(),
        false,
      ),
      summaries.read(
        'Indexer managers',
        () =>
            TorrentProviderStorage.getIndexerManagerConfigs(forSettings: true),
        [],
      ),
      summaries.read(
        'Premiumize',
        () => PremiumizeStorage.hasPremiumizeCredential(),
        false,
      ),
      summaries.read(
        'AllDebrid',
        () => AllDebridStorage.hasAllDebridCredential(),
        false,
      ),
      summaries.read('Simkl', () => SimklStorage.hasSimklCredential(), false),
      summaries.read('Simkl', () => SimklStorage.getSimklUsername(), null),
      summaries.read(
        'MDBList',
        () => MdblistStorage.hasMdblistCredential(),
        false,
      ),
      summaries.read(
        'MDBList',
        () => MdblistStorage.getMdblistUsername(),
        null,
      ),
      summaries.read(
        'TV keyboard',
        () => TvDisplayStorage.getTvKeyboardEnabled(),
        _summaries.tvKeyboardEnabled,
      ),
      summaries.read(
        'TV scale',
        () => TvDisplayStorage.getTvUiScalePercent(),
        _summaries.tvUiScalePercent,
      ),
      summaries.read(
        'TV home',
        () => HomeAppearanceStorage.getTvHomeStyle(),
        _summaries.tvHomeStyle,
      ),
      summaries.read(
        'TV sidebar',
        () => SidebarStorage.getTvSidebarStyle(),
        _summaries.tvSidebarStyle,
      ),
      summaries.read(
        'Discover layout',
        () => DiscoverStorage.getDiscoverLayout(),
        _summaries.discoverLayout,
      ),
      summaries.read(
        'IPTV style',
        () => IptvAppearanceStorage.getIptvStyle(),
        _summaries.iptvStyle,
      ),
      summaries.read(
        'Player guide',
        () => IptvAppearanceStorage.getIptvPlayerGuideStyle(),
        _summaries.playerGuideStyle,
      ),
      summaries.read(
        'Phone navigation',
        () => SidebarStorage.getPhoneNavStyle(),
        _summaries.phoneNavStyle,
      ),
      summaries.read(
        'Text brightness',
        () => ThemeStorage.getTextBrightness(),
        _summaries.textBrightness,
      ),
      summaries.read(
        'Launch animation',
        () => LaunchIdentStorage.getLaunchAnimation(),
        _summaries.launchAnimation,
      ),
      summaries.read(
        'Detail page',
        () => DetailPageStorage.getDetailPageStyle(),
        _summaries.detailPageStyle,
      ),
      summaries.read(
        'Render quality',
        () => TvDisplayStorage.getTvRenderQuality(),
        _summaries.tvRenderQuality,
      ),
      summaries.read(
        'Detail theme',
        () => DetailPageStorage.getDetailTheme(),
        _summaries.detailTheme,
      ),
      summaries.read(
        'Parents guide',
        () => DetailPageStorage.getParentsGuideStyle(),
        _summaries.parentsGuideStyle,
      ),
      summaries.read(
        'Artwork quality',
        () => TvDisplayStorage.getTvHeroArtworkQuality(),
        _summaries.tvHeroArtworkQuality,
      ),
      summaries.read(
        'Player dock',
        () => PlayerAppearanceStorage.getPlayerDockStyle(),
        _summaries.playerDockStyle,
      ),
      summaries.read(
        'Dock palette',
        () => PlayerAppearanceStorage.getPlayerDockPalette(),
        _summaries.playerDockPalette,
      ),
      summaries.read(
        'Dock size',
        () => PlayerAppearanceStorage.getPlayerDockSize(),
        _summaries.playerDockSize,
      ),
      summaries.read(
        'Desktop sidebar',
        () => SidebarStorage.getDesktopSidebarStyle(),
        _summaries.desktopSidebarStyle,
      ),
      summaries.read(
        'Debrify TV',
        () => DebrifyTvStorage.getDebrifyTvStyle(),
        _summaries.debrifyTvStyle,
      ),
      summaries.read(
        'TV controls',
        () => PlayerAppearanceStorage.getTvPlayerControlsStyle(),
        _summaries.tvPlayerControlsStyle,
      ),
      summaries.read(
        'TV player',
        () => DebrifyTvStorage.getDebrifyTvPlayerStyle(),
        _summaries.debrifyTvPlayerStyle,
      ),
      summaries.read(
        'Play loader',
        () => PlayerAppearanceStorage.getPlayLoaderStyle(),
        _summaries.playLoaderStyle,
      ),
      summaries.read(
        'Diagnostics',
        () => _deps.activeProfileMayExportDiagnostics(),
        false,
      ),
      summaries.read(
        'Pending credentials',
        () => _deps.pendingCredentialTypes(),
        <ConnectionResourceType>{},
      ),
      summaries.read(
        'IPTV',
        () => IptvPlaylistStorage.getIptvPlaylists(forSettings: true),
        [],
      ),
      summaries.read(
        'Alpha updates',
        () => DeviceStorage.getUpdateIncludeAlphaEnabled(),
        false,
      ),
      summaries.read(
        'Media servers',
        () async => (await MediaServerService.connections()).length,
        0,
      ),
    ]);

    if (!_deps.mounted() || ProfileRuntime.scope.value != startingScope) return;
    _summaries.summaryFailures = summaries.failures;
    _summaries.summaryUnavailable = summaries.unavailable;

    final rdConnected = results[0] as bool;
    final torConnected = results[1] as bool;
    final pikpakAuth = results[2] as bool;
    final webDavEnabled = results[3] as bool;
    final webDavServers = results[4] as List<WebDavConfig>;
    final traktConnected = results[5] as bool;
    final traktExpiry = results[6] as int?;
    final traktUsername = results[7] as String?;
    final packageInfo = results[8] as PackageInfo;
    final isAndroidTv = results[9] as bool;
    final autoCheckEnabled = results[10] as bool;
    final indexerManagers = results[11] as List;
    final premiumizeConnected = results[12] as bool;
    final allDebridConnected = results[13] as bool;
    final simklConnected = results[14] as bool;
    final simklUsername = results[15] as String?;
    final mdblistConnected = results[16] as bool;
    final mdblistUsername = results[17] as String?;
    final tvKeyboardEnabled = results[18] as bool;
    final tvUiScalePercent = results[19] as int;
    final tvHomeStyle = results[20] as String;
    final tvSidebarStyle = results[21] as String;
    final discoverLayout = results[22] as String;
    final iptvStyle = results[23] as String;
    final playerGuideStyle = results[24] as String;
    final phoneNavStyle = results[25] as String;
    final textBrightness = results[26] as String;
    final launchAnimation = results[27] as String;
    final detailPageStyle = results[28] as String;
    final tvRenderQuality = results[29] as TvRenderQuality;
    final detailTheme = results[30] as String;
    final parentsGuideStyle = results[31] as String;
    final tvHeroArtworkQuality = results[32] as TvHeroArtworkQuality;
    // Later summary fields stay appended at the END of the Future.wait above,
    // so the long-established indices 0..32 never move.
    final playerDockStyle = results[33] as String;
    final playerDockPalette = results[34] as String;
    final playerDockSize = results[35] as String;
    final desktopSidebarStyle = results[36] as String;
    final debrifyTvStyle = results[37] as String;
    final tvPlayerControlsStyle = results[38] as String;
    final debrifyTvPlayerStyle = results[39] as String;
    final playLoaderStyle = results[40] as String;
    final diagnosticExportVisible = results[41] as bool;
    final pendingCredentialTypes = results[42] as Set<ConnectionResourceType>;
    final configuredIptvPlaylists = results[43] as List;
    final includeAlphaUpdates = results[44] as bool;
    _summaries.mediaServerCount = results[45] as int;

    // Set initial state from cached data
    // Use cached account info if available
    if (rdConnected) {
      final user = AccountService.currentUser;
      _summaries.realDebridConnected = true;
      if (user != null) {
        _deps.applyRdUserInfo(user);
      } else {
        _summaries.realDebridStatus = 'Connected';
        _summaries.realDebridCaption = 'Loading account info...';
      }
    }

    if (torConnected) {
      final torboxUser = TorboxAccountService.currentUser;
      _summaries.torboxConnected = true;
      if (torboxUser != null) {
        _deps.applyTorboxUserInfo(torboxUser);
      } else {
        _summaries.torboxStatus = 'Connected';
        _summaries.torboxCaption = 'Loading account info...';
      }
    }

    if (premiumizeConnected) {
      final premiumizeUser = PremiumizeAccountService.currentUser;
      _summaries.premiumizeConnected = true;
      if (premiumizeUser != null) {
        _deps.applyPremiumizeUserInfo(premiumizeUser);
      } else {
        _summaries.premiumizeStatus = 'Connected';
        _summaries.premiumizeCaption = 'Loading account info...';
      }
    }

    if (allDebridConnected) {
      final allDebridUser = AllDebridAccountService.currentUser;
      _summaries.allDebridConnected = true;
      if (allDebridUser != null) {
        _deps.applyAllDebridUserInfo(allDebridUser);
      } else {
        _summaries.allDebridStatus = 'Connected';
        _summaries.allDebridCaption = 'Loading account info...';
      }
    }

    if (pikpakAuth) {
      _summaries.pikpakConnected = true;
      _summaries.pikpakStatus = 'Active';
      _summaries.pikpakCaption = 'Logged in';
    }

    if (webDavEnabled && webDavServers.isNotEmpty) {
      _summaries.webDavConnected = true;
      _summaries.webDavStatus = 'Active';
      final first = webDavServers.first;
      final host = Uri.tryParse(first.baseUrl)?.host;
      final label = (host != null && host.isNotEmpty) ? host : first.baseUrl;
      _summaries.webDavCaption = webDavServers.length == 1
          ? label
          : '$label (+${webDavServers.length - 1} more)';
    } else {
      _summaries.webDavConnected = false;
      _summaries.webDavStatus = 'Not connected';
      _summaries.webDavCaption = 'Tap to connect';
    }

    final traktExpired =
        traktExpiry != null &&
        DateTime.now().millisecondsSinceEpoch >= traktExpiry;
    if (traktConnected) {
      if (!traktExpired) {
        _summaries.traktConnected = true;
        _summaries.traktStatus = 'Active';
        _summaries.traktCaption = traktUsername != null
            ? 'Logged in as $traktUsername'
            : 'Logged in';
      } else {
        _summaries.traktStatus = 'Expired';
        _summaries.traktCaption = 'Tap to reconnect';
      }
    }

    // Simkl's PIN-issued tokens don't expire, so unlike Trakt there's no
    // "Expired" branch here — a stored token means connected.
    if (simklConnected) {
      _summaries.simklConnected = true;
      _summaries.simklStatus = 'Active';
      _summaries.simklCaption = simklUsername != null
          ? 'Logged in as $simklUsername'
          : 'Logged in';
    } else {
      _summaries.simklConnected = false;
      _summaries.simklStatus = 'Not connected';
      _summaries.simklCaption = 'Tap to connect';
    }

    // MDBList uses a plain API key (no expiry) — a stored key means connected.
    // Reset on the empty branch (like WebDAV above) so the card clears after a
    // logout, since this method re-runs when returning from the settings page.
    if (mdblistConnected) {
      _summaries.mdblistConnected = true;
      _summaries.mdblistStatus = 'Active';
      _summaries.mdblistCaption = mdblistUsername != null
          ? 'Logged in as $mdblistUsername'
          : 'Logged in';
    } else {
      _summaries.mdblistConnected = false;
      _summaries.mdblistStatus = 'Not connected';
      _summaries.mdblistCaption = 'Tap to connect';
    }

    if (indexerManagers.isNotEmpty) {
      _summaries.indexerManagersConfigured = true;
      _summaries.indexerManagersStatus = 'Active';
      _summaries.indexerManagersCaption =
          '${indexerManagers.length} engine${indexerManagers.length == 1 ? '' : 's'} configured';
    }

    void pending(
      Set<ConnectionResourceType> types,
      bool ownCredentialPresent,
      void Function() apply,
    ) {
      if (shouldApplyPendingCredentialOverride(
        pendingTypes: pendingCredentialTypes,
        providerTypes: types,
        ownCredentialPresent: ownCredentialPresent,
      )) {
        apply();
      }
    }

    const pendingCaption = 'credentials pending owner sign-in';
    _summaries.iptvCredentialsPending = shouldApplyPendingCredentialOverride(
      pendingTypes: pendingCredentialTypes,
      providerTypes: const {
        ConnectionResourceType.iptvM3u,
        ConnectionResourceType.iptvXtream,
        ConnectionResourceType.xmltv,
      },
      ownCredentialPresent: configuredIptvPlaylists.isNotEmpty,
    );
    pending(const {ConnectionResourceType.realDebrid}, rdConnected, () {
      _summaries.realDebridConnected = true;
      _summaries.realDebridStatus = 'Attention';
      _summaries.realDebridCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.torbox}, torConnected, () {
      _summaries.torboxConnected = true;
      _summaries.torboxStatus = 'Attention';
      _summaries.torboxCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.premiumize}, premiumizeConnected, () {
      _summaries.premiumizeConnected = true;
      _summaries.premiumizeStatus = 'Attention';
      _summaries.premiumizeCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.allDebrid}, allDebridConnected, () {
      _summaries.allDebridConnected = true;
      _summaries.allDebridStatus = 'Attention';
      _summaries.allDebridCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.pikpak}, pikpakAuth, () {
      _summaries.pikpakConnected = true;
      _summaries.pikpakStatus = 'Attention';
      _summaries.pikpakCaption = pendingCaption;
    });
    pending(
      const {ConnectionResourceType.webDav},
      webDavEnabled && webDavServers.isNotEmpty,
      () {
        _summaries.webDavConnected = true;
        _summaries.webDavStatus = 'Attention';
        _summaries.webDavCaption = pendingCaption;
      },
    );
    pending(const {ConnectionResourceType.trakt}, traktConnected, () {
      _summaries.traktConnected = true;
      _summaries.traktStatus = 'Attention';
      _summaries.traktCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.simkl}, simklConnected, () {
      _summaries.simklConnected = true;
      _summaries.simklStatus = 'Attention';
      _summaries.simklCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.mdblist}, mdblistConnected, () {
      _summaries.mdblistConnected = true;
      _summaries.mdblistStatus = 'Attention';
      _summaries.mdblistCaption = pendingCaption;
    });
    pending(
      const {ConnectionResourceType.jackett, ConnectionResourceType.prowlarr},
      indexerManagers.isNotEmpty,
      () {
        _summaries.indexerManagersConfigured = true;
        _summaries.indexerManagersStatus = 'Attention';
        _summaries.indexerManagersCaption = pendingCaption;
      },
    );

    _summaries.appVersion =
        '${packageInfo.version} (${packageInfo.buildNumber})';
    _summaries.currentVersionName = packageInfo.version;
    _summaries.isAndroidTv = isAndroidTv;
    DiagnosticLog.instance.recordEvent(
      source: 'app',
      event: 'app_metadata',
      fields: <String, Object?>{
        'version': DiagnosticLabel(packageInfo.version),
        'build': DiagnosticLabel(packageInfo.buildNumber),
        'androidTv': isAndroidTv,
      },
    );
    _summaries.loading = false;
    _summaries.autoUpdateChecksEnabled = autoCheckEnabled;
    _summaries.includeAlphaUpdates = includeAlphaUpdates;
    _summaries.tvKeyboardEnabled = tvKeyboardEnabled;
    _summaries.tvUiScalePercent = tvUiScalePercent;
    _summaries.tvRenderQuality = tvRenderQuality;
    _summaries.tvHomeStyle = tvHomeStyle;
    _summaries.tvSidebarStyle = tvSidebarStyle;
    _summaries.discoverLayout = discoverLayout;
    _summaries.iptvStyle = iptvStyle;
    _summaries.debrifyTvStyle = debrifyTvStyle;
    _summaries.playerGuideStyle = playerGuideStyle;
    _summaries.playLoaderStyle = playLoaderStyle;
    _summaries.tvPlayerControlsStyle = tvPlayerControlsStyle;
    _summaries.debrifyTvPlayerStyle = debrifyTvPlayerStyle;
    _summaries.playerDockStyle = playerDockStyle;
    _summaries.playerDockPalette = playerDockPalette;
    _summaries.playerDockSize = playerDockSize;
    _summaries.phoneNavStyle = phoneNavStyle;
    _summaries.desktopSidebarStyle = desktopSidebarStyle;
    _summaries.textBrightness = textBrightness;
    _summaries.launchAnimation = launchAnimation;
    _summaries.detailPageStyle = detailPageStyle;
    _summaries.detailTheme = detailTheme;
    _summaries.parentsGuideStyle = parentsGuideStyle;
    _summaries.tvHeroArtworkQuality = tvHeroArtworkQuality;
    _summaries.diagnosticExportVisible = diagnosticExportVisible;

    _deps.setState(() {});

    // Phase 2: Refresh account info from network in background
    if (rdConnected) {
      AccountService.refreshUserInfo().then((_) {
        if (!_deps.mounted()) return;
        final user = AccountService.currentUser;
        if (user != null) {
          _deps.setState(() => _deps.applyRdUserInfo(user));
        }
      });
    }

    if (torConnected) {
      TorboxAccountService.refreshUserInfo().then((_) {
        if (!_deps.mounted()) return;
        final torboxUser = TorboxAccountService.currentUser;
        if (torboxUser != null) {
          _deps.setState(() => _deps.applyTorboxUserInfo(torboxUser));
        }
      });
    }

    if (premiumizeConnected) {
      PremiumizeAccountService.refreshUserInfo().then((_) {
        if (!_deps.mounted()) return;
        final premiumizeUser = PremiumizeAccountService.currentUser;
        if (premiumizeUser != null) {
          _deps.setState(() => _deps.applyPremiumizeUserInfo(premiumizeUser));
        }
      });
    }

    if (allDebridConnected) {
      AllDebridAccountService.refreshUserInfo().then((_) {
        if (!_deps.mounted()) return;
        final allDebridUser = AllDebridAccountService.currentUser;
        if (allDebridUser != null) {
          _deps.setState(() => _deps.applyAllDebridUserInfo(allDebridUser));
        }
      });
    }
  }
}
