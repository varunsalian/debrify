import 'package:debrify/features/addon_hub/models/addon_hub_kinds.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_market_state.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AddonHubLoadingDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  AddonHubInstalledState installedState,
  AddonHubMarketState marketState,
});

class AddonHubLoading {
  AddonHubLoading(this._deps);
  final AddonHubLoadingDeps _deps;

  Future<void> loadDebridState() async {
    final configured = await Future.wait([
      RealDebridStorage.hasRealDebridCredential(),
      TorboxStorage.hasTorboxCredential(),
      PremiumizeStorage.hasPremiumizeCredential(),
      AllDebridStorage.hasAllDebridCredential(),
    ]);
    final has = configured.any((value) => value);
    if (_deps.mounted()) {
      _deps.setState(() => _deps.installedState.hasDebrid = has);
    }
  }

  void onAddonsChanged() => loadInstalled();

  Future<void> loadInstalled() async {
    final revision = ++_deps.installedState.installedLoadRevision;
    if (_deps.mounted()) {
      _deps.setState(() => _deps.installedState.installedLoading = true);
    }
    try {
      // This is the management inventory. It must include disabled addons so
      // they remain visible and can be enabled again; the normal read path
      // intentionally excludes profile-locally disabled rows for playback.
      final results = await Future.wait<Object?>([
        _deps.installedState.stremio.getAddonsForManagement(),
        _deps.installedState.stremio.getMetadataProviderPreference(),
      ]);
      final addons = results[0] as List<StremioAddon>;
      final metadataPreference = results[1] as String?;
      if (_deps.mounted() &&
          revision == _deps.installedState.installedLoadRevision) {
        _deps.setState(() {
          _deps.installedState.installed = addons;
          _deps.installedState.metadataProviderPreference = metadataPreference;
          _deps.installedState.installedLoading = false;
        });
      }
    } catch (_) {
      if (_deps.mounted() &&
          revision == _deps.installedState.installedLoadRevision) {
        _deps.setState(() => _deps.installedState.installedLoading = false);
      }
    }
  }

  Future<void> loadMarket(AddonHubSource source, {bool force = false}) async {
    if (!_deps.mounted()) return;
    _deps.setState(() {
      _deps.marketState.marketLoading = true;
      _deps.marketState.marketError = null;
      _deps.marketState.marketLoadedFor = source;
    });
    try {
      final addons = source == AddonHubSource.community
          ? await _deps.marketState.marketplace.fetchCommunity(
              forceRefresh: force,
            )
          : await _deps.marketState.marketplace.fetchOfficial(
              forceRefresh: force,
            );
      if (_deps.mounted() && _deps.marketState.marketLoadedFor == source) {
        _deps.setState(() {
          _deps.marketState.market = addons;
          _deps.marketState.marketLoading = false;
        });
      }
    } catch (e) {
      if (_deps.mounted() && _deps.marketState.marketLoadedFor == source) {
        _deps.setState(() {
          _deps.marketState.marketError = e.toString().replaceFirst(
            'Exception: ',
            '',
          );
          _deps.marketState.marketLoading = false;
        });
      }
    }
  }
}
