import 'dart:async';

import 'package:debrify/features/debrify_tv/application/debrify_tv_random_start.dart';
import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/services/android_native_downloader.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/pikpak_tv_service.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/utils/debrify_tv_filters.dart';

class DebrifyTvSettingsLoader {
  final DebrifyTvDependencies _deps;
  DebrifyTvSettingsLoader(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  String determineDefaultProvider(
    String? preferred,
    bool rdAvailable,
    bool torboxAvailable,
    bool pikpakAvailable,
    bool premiumizeAvailable,
    bool allDebridAvailable,
  ) {
    // If user has a preferred provider that's available, use it
    if (preferred == DebrifyTvConstants.providerPremiumize &&
        premiumizeAvailable) {
      return DebrifyTvConstants.providerPremiumize;
    }
    if (preferred == DebrifyTvConstants.providerAllDebrid &&
        allDebridAvailable) {
      return DebrifyTvConstants.providerAllDebrid;
    }
    if (preferred == DebrifyTvConstants.providerPikPak && pikpakAvailable) {
      return DebrifyTvConstants.providerPikPak;
    }
    if (preferred == DebrifyTvConstants.providerTorbox && torboxAvailable) {
      return DebrifyTvConstants.providerTorbox;
    }
    if (preferred == DebrifyTvConstants.providerRealDebrid && rdAvailable) {
      return DebrifyTvConstants.providerRealDebrid;
    }

    // Fallback: pick first available provider
    if (rdAvailable) {
      return DebrifyTvConstants.providerRealDebrid;
    }
    if (torboxAvailable) {
      return DebrifyTvConstants.providerTorbox;
    }
    if (premiumizeAvailable) {
      return DebrifyTvConstants.providerPremiumize;
    }
    if (allDebridAvailable) {
      return DebrifyTvConstants.providerAllDebrid;
    }
    if (pikpakAvailable) {
      return DebrifyTvConstants.providerPikPak;
    }

    // No provider available, default to RD (will show as unavailable)
    return DebrifyTvConstants.providerRealDebrid;
  }

  bool isProviderSelectable(String provider) {
    if (provider == DebrifyTvConstants.providerTorbox) {
      return _owners.settings.torboxAvailable;
    }
    if (provider == DebrifyTvConstants.providerPikPak) {
      return _owners.settings.pikpakAvailable;
    }
    if (provider == DebrifyTvConstants.providerPremiumize) {
      return _owners.settings.premiumizeAvailable;
    }
    if (provider == DebrifyTvConstants.providerAllDebrid) {
      return _owners.settings.allDebridAvailable;
    }
    return _owners.settings.rdAvailable;
  }

  Future<void> loadSettings() async {
    final startRandom = await DebrifyTvStorage.getDebrifyTvStartRandom();
    final randomStartPercent =
        await DebrifyTvStorage.getDebrifyTvRandomStartPercent();
    // Hardcoded to false - no longer loading from storage
    const hideOptions = false;
    final showChannelName =
        await DebrifyTvStorage.getDebrifyTvShowChannelName();
    final showVideoTitle = await DebrifyTvStorage.getDebrifyTvShowVideoTitle();
    // hideBackButton is hardcoded to false - no longer loading from storage
    final avoidNsfw = await _owners.settings.settingsManager.getGlobalAvoidNsfw(
      true,
    );
    final rdSkipBlocked = await RealDebridStorage.getRdSkipBlockedTorrents();
    final tvFilters = await DebrifyTvFilters.load();
    final storedProvider = await DebrifyTvStorage.getDebrifyTvProvider();
    final hasStoredProvider = await DebrifyTvStorage.hasDebrifyTvProvider();
    final rdIntegrationEnabled =
        await RealDebridStorage.getRealDebridIntegrationEnabled();
    final rdKey = await RealDebridStorage.getApiKey();
    final torboxIntegrationEnabled =
        await TorboxStorage.getTorboxIntegrationEnabled();
    final torboxKey = await TorboxStorage.getTorboxApiKey();

    final registry = EngineRegistry.instance;
    await registry.initialize();
    final keywordEngines = registry.getKeywordSearchEngines();
    final tvEngines = registry
        .getTvModeEngines()
        .where((engine) => engine.supportsKeywordSearch)
        .toList();
    final tvEngineStates = <String, bool>{
      for (final engine in keywordEngines) engine.name: false,
    };
    final tvSmallChannelMaxByEngine = <String, int>{};
    final tvLargeChannelMaxByEngine = <String, int>{};
    final tvQuickPlayMaxByEngine = <String, int>{};

    for (final engine in tvEngines) {
      final tvMode = engine.tvModeConfig;
      if (tvMode == null) {
        continue;
      }
      final engineId = engine.name;
      tvEngineStates[engineId] = await _owners.settings.settingsManager
          .getTvEnabled(engineId, tvMode.enabledDefault);
      tvSmallChannelMaxByEngine[engineId] = await _owners
          .settings
          .settingsManager
          .getTvSmallChannelMax(engineId, tvMode.smallChannel.maxResults);
      tvLargeChannelMaxByEngine[engineId] = await _owners
          .settings
          .settingsManager
          .getTvLargeChannelMax(engineId, tvMode.largeChannel.maxResults);
      tvQuickPlayMaxByEngine[engineId] = await _owners.settings.settingsManager
          .getTvQuickPlayMax(engineId, tvMode.quickPlay.maxResults);
    }

    // Global TV settings
    final channelBatchSize = await _owners.settings.settingsManager
        .getGlobalBatchSize(4);
    final keywordThreshold = await _owners.settings.settingsManager
        .getGlobalKeywordThreshold(10);
    final minTorrentsPerKeyword = await _owners.settings.settingsManager
        .getGlobalMinTorrentsPerKeyword(5);
    final quickPlayMaxKeywords = await _owners.settings.settingsManager
        .getGlobalMaxKeywords(5);

    final rdAvailable =
        rdIntegrationEnabled && rdKey != null && rdKey.isNotEmpty;
    final torboxAvailable =
        torboxIntegrationEnabled && torboxKey != null && torboxKey.isNotEmpty;
    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    final premiumizeIntegrationEnabled =
        await PremiumizeStorage.getPremiumizeIntegrationEnabled();
    final premiumizeKey = await PremiumizeStorage.getPremiumizeApiKey();
    final premiumizeAvailable =
        premiumizeIntegrationEnabled &&
        premiumizeKey != null &&
        premiumizeKey.isNotEmpty;
    final allDebridIntegrationEnabled =
        await AllDebridStorage.getAllDebridIntegrationEnabled();
    final allDebridKey = await AllDebridStorage.getAllDebridApiKey();
    final allDebridAvailable =
        allDebridIntegrationEnabled &&
        allDebridKey != null &&
        allDebridKey.isNotEmpty;
    final defaultProvider = _sections.settings.determineDefaultProvider(
      hasStoredProvider ? storedProvider : null,
      rdAvailable,
      torboxAvailable,
      pikpakAvailable,
      premiumizeAvailable,
      allDebridAvailable,
    );
    final isTv = await AndroidNativeDownloader.isTelevision();

    if (_deps.mounted()) {
      _deps.setState(() {
        _owners.settings.startRandom = startRandom;
        _owners.settings.randomStartPercent = clampDebrifyTvRandomStartPercent(
          randomStartPercent,
        );
        _owners.settings.hideSeekbar = hideOptions;
        _owners.settings.showChannelName = showChannelName;
        _owners.settings.showVideoTitle = showVideoTitle;
        _owners.settings.hideOptions = false; // Hardcoded to false
        _owners.settings.hideBackButton = false; // Hardcoded to false
        _owners.settings.rdAvailable = rdAvailable;
        _owners.settings.torboxAvailable = torboxAvailable;
        _owners.settings.pikpakAvailable = pikpakAvailable;
        _owners.settings.premiumizeAvailable = premiumizeAvailable;
        _owners.settings.allDebridAvailable = allDebridAvailable;
        _owners.settings.provider = defaultProvider;
        _owners.settings.isAndroidTv = isTv;

        _owners.settings.quickStartRandom = startRandom;
        _owners.settings.quickRandomStartPercent =
            clampDebrifyTvRandomStartPercent(randomStartPercent);
        _owners.settings.quickHideSeekbar = hideOptions;
        _owners.settings.quickShowChannelName = showChannelName;
        _owners.settings.quickShowVideoTitle = showVideoTitle;
        _owners.settings.quickHideOptions = false; // Hardcoded to false
        _owners.settings.quickHideBackButton = false; // Hardcoded to false
        _owners.settings.quickAvoidNsfw = avoidNsfw;
        _owners.settings.rdSkipBlockedTorrents = rdSkipBlocked;
        _owners.settings.quickProvider = defaultProvider;
        _owners.settings.tvFilters = tvFilters;
        // The filter is an INPUT to the memoised stage numbers: anything
        // computed before this load landed used the empty default.
        _owners.stage.spotlightStats.clear();

        // Update search settings
        _owners.settings.tvEngineStates
          ..clear()
          ..addAll(tvEngineStates);
        _owners.settings.tvSmallChannelMaxByEngine
          ..clear()
          ..addAll(tvSmallChannelMaxByEngine);
        _owners.settings.tvLargeChannelMaxByEngine
          ..clear()
          ..addAll(tvLargeChannelMaxByEngine);
        _owners.settings.tvQuickPlayMaxByEngine
          ..clear()
          ..addAll(tvQuickPlayMaxByEngine);
        _owners.settings.channelBatchSize = channelBatchSize;
        _owners.settings.keywordThreshold = keywordThreshold;
        _owners.settings.minTorrentsPerKeyword = minTorrentsPerKeyword;
        _owners.settings.quickPlayMaxKeywords = quickPlayMaxKeywords;
      });
      // Outside the setState callback: recomputing the focused channel's
      // numbers schedules its own rebuild.
      _sections.stage.refreshSpotlightStatsIfFocused(
        _owners.stage.spotlightFocusedId,
      );
    }

    if (await DebrifyTvStorage.getDebrifyTvHideSeekbar() != hideOptions) {
      unawaited(DebrifyTvStorage.saveDebrifyTvHideSeekbar(hideOptions));
    }

    if (defaultProvider != storedProvider) {
      await DebrifyTvStorage.saveDebrifyTvProvider(defaultProvider);
    }
  }

  Future<void> syncProviderAvailability() async {
    final rdIntegrationEnabled =
        await RealDebridStorage.getRealDebridIntegrationEnabled();
    final rdKey = await RealDebridStorage.getApiKey();
    final torboxIntegrationEnabled =
        await TorboxStorage.getTorboxIntegrationEnabled();
    final torboxKey = await TorboxStorage.getTorboxApiKey();
    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    final premiumizeIntegrationEnabled =
        await PremiumizeStorage.getPremiumizeIntegrationEnabled();
    final premiumizeKey = await PremiumizeStorage.getPremiumizeApiKey();
    final premiumizeAvailable =
        premiumizeIntegrationEnabled &&
        premiumizeKey != null &&
        premiumizeKey.isNotEmpty;
    final allDebridIntegrationEnabled =
        await AllDebridStorage.getAllDebridIntegrationEnabled();
    final allDebridKey = await AllDebridStorage.getAllDebridApiKey();
    final allDebridAvailable =
        allDebridIntegrationEnabled &&
        allDebridKey != null &&
        allDebridKey.isNotEmpty;

    final rdAvailable =
        rdIntegrationEnabled && rdKey != null && rdKey.isNotEmpty;
    final torboxAvailable =
        torboxIntegrationEnabled && torboxKey != null && torboxKey.isNotEmpty;

    final nextChannelProvider = _sections.settings.determineDefaultProvider(
      _owners.settings.provider,
      rdAvailable,
      torboxAvailable,
      pikpakAvailable,
      premiumizeAvailable,
      allDebridAvailable,
    );
    final nextQuickProvider = _sections.settings.determineDefaultProvider(
      _owners.settings.quickProvider,
      rdAvailable,
      torboxAvailable,
      pikpakAvailable,
      premiumizeAvailable,
      allDebridAvailable,
    );

    if (!_deps.mounted()) return;
    final providerChanged = nextChannelProvider != _owners.settings.provider;
    _deps.setState(() {
      _owners.settings.rdAvailable = rdAvailable;
      _owners.settings.torboxAvailable = torboxAvailable;
      _owners.settings.pikpakAvailable = pikpakAvailable;
      _owners.settings.premiumizeAvailable = premiumizeAvailable;
      _owners.settings.allDebridAvailable = allDebridAvailable;
      _owners.settings.provider = nextChannelProvider;
      _owners.settings.quickProvider = nextQuickProvider;
    });

    if (providerChanged) {
      await DebrifyTvStorage.saveDebrifyTvProvider(nextChannelProvider);
    }
  }

  String providerDisplay(String provider) {
    if (provider == DebrifyTvConstants.providerTorbox) return 'Torbox';
    if (provider == DebrifyTvConstants.providerPikPak) return 'PikPak';
    if (provider == DebrifyTvConstants.providerPremiumize) return 'Premiumize';
    if (provider == DebrifyTvConstants.providerAllDebrid) return 'AllDebrid';
    return 'Real Debrid';
  }
}
