import 'dart:async' show unawaited;

import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart';
import 'package:debrify/screens/settings/iptv_settings_two_pane.dart';
import 'package:debrify/screens/settings/iptv_style_page.dart';
import 'package:debrify/screens/settings/player_guide_style_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/iptv_catalog_refresh_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:debrify/theme/app_looks.dart';
import 'package:debrify/widgets/iptv/iptv_startup_channel_picker.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsPreferencesActionsDeps = ({
  Future<void> Function(Future<void> Function() body) runProfileAction,
  BuildContext Function() context,
  IptvSettingsPreferencesOwner preferencesOwner,
  bool Function() mounted,
  void Function(VoidCallback) setState,
});

class IptvSettingsPreferencesActions {
  IptvSettingsPreferencesActions(this._deps);
  final IptvSettingsPreferencesActionsDeps _deps;

  Future<void> pickAutoRefresh() => _deps.runProfileAction(() async {
    final startingScope = ProfileRuntime.scope.value;
    final hours = await showDialog<int>(
      context: _deps.context(),
      builder: (_) => IptvAutoRefreshDialog(
        intervalHours: _deps.preferencesOwner.autoRefreshHours,
      ),
    );
    if (hours == null ||
        !_deps.mounted() ||
        ProfileRuntime.scope.value != startingScope) {
      return;
    }
    await _deps.runProfileAction(() async {
      if (!_deps.mounted() || ProfileRuntime.scope.value != startingScope) {
        return;
      }
      await IptvCatalogRefreshService.setIntervalHours(hours);
      if (!_deps.mounted() || ProfileRuntime.scope.value != startingScope) {
        return;
      }
      _deps.setState(() => _deps.preferencesOwner.autoRefreshHours = hours);
      unawaited(IptvCatalogRefreshService.instance.refreshDue());
    });
  });

  /// Subtitle for the "specific channel" row — names the pinned channel so the
  /// setting is readable without opening the picker.
  String get startupChannelLabel {
    final channel = _deps.preferencesOwner.startupChannel;
    if (channel == null) return 'None chosen yet';
    final name = channel['name'];
    final number = channel['channelNumber'];
    if (name is! String || name.isEmpty) return 'None chosen yet';
    return number is num ? 'CH $number  ·  $name' : name;
  }

  /// Names the remembered channel, so "last watched" is verifiable at a glance
  /// rather than a promise the user has to reboot to test.
  String get lastLiveChannelLabel {
    final channel = _deps.preferencesOwner.lastLiveChannel;
    final name = channel?['name'];
    if (name is! String || name.isEmpty) return 'unknown';
    final number = channel?['channelNumber'];
    return number is num ? 'CH $number  ·  $name' : name;
  }

  Future<void> setStartupMode(String? mode) =>
      _deps.runProfileAction(() => setStartupModeForProfile(mode));

  Future<void> setStartupModeForProfile(String? mode) async {
    if (mode == null) return;
    await StartupIptvStorage.setStartupIptvMode(mode);
    if (_deps.mounted()) {
      _deps.setState(() => _deps.preferencesOwner.startupMode = mode);
    }
    // Choosing "a specific channel" with none set yet goes straight to the
    // picker — otherwise the mode is selected but inert, which reads as broken.
    if (mode == StartupIptvStorage.startupIptvModePinned &&
        _deps.preferencesOwner.startupChannel == null) {
      await pickStartupChannel();
    }
  }

  Future<void> setStartupEnabled(bool enabled) =>
      _deps.runProfileAction(() async {
        await StartupIptvStorage.setStartupIptvEnabled(enabled);
        if (_deps.mounted()) {
          _deps.setState(() => _deps.preferencesOwner.startupEnabled = enabled);
        }
      });

  Future<void> setTrackContinueWatching(bool value) =>
      _deps.runProfileAction(() => setTrackContinueWatchingForProfile(value));

  Future<void> setTrackContinueWatchingForProfile(bool value) async {
    await IptvHistoryStorage.setIptvTrackContinueWatching(value);
    if (_deps.mounted()) {
      _deps.setState(
        () => _deps.preferencesOwner.trackContinueWatching = value,
      );
    }
  }

  Future<void> setChannelPreviewEnabled(bool value) =>
      _deps.runProfileAction(() => setChannelPreviewEnabledForProfile(value));

  Future<void> setChannelPreviewEnabledForProfile(bool value) async {
    await IptvAppearanceStorage.setIptvChannelPreviewEnabled(value);
    if (_deps.mounted()) {
      _deps.setState(
        () => _deps.preferencesOwner.channelPreviewEnabled = value,
      );
    }
  }

  Future<void> setIptvStyle(String style) =>
      _deps.runProfileAction(() => setIptvStyleForProfile(style));

  Future<void> setIptvStyleForProfile(String style) async {
    // Persist BEFORE reflecting the choice: the IPTV page re-reads the pref
    // the moment this route pops, and an unawaited write could lose that race.
    // A direct pick here has the same priority as the standalone picker over
    // any Look bundle that is still being applied.
    LookApplier.noteExternalWrite('iptv_style');
    await IptvAppearanceStorage.setIptvStyle(style);
    if (_deps.mounted()) {
      _deps.setState(() => _deps.preferencesOwner.iptvStyle = style);
    }
  }

  Future<void> setPlayerGuideStyle(String style) =>
      _deps.runProfileAction(() => setPlayerGuideStyleForProfile(style));

  Future<void> setPlayerGuideStyleForProfile(String style) async {
    // Same persist-before-setState contract as [_setIptvStyle]: the player
    // reads the pref at launch, which can happen the moment this route pops.
    await IptvAppearanceStorage.setIptvPlayerGuideStyle(style);
    if (_deps.mounted()) {
      _deps.setState(() => _deps.preferencesOwner.playerGuideStyle = style);
    }
  }

  Future<void> pickStartupChannel() =>
      _deps.runProfileAction(pickStartupChannelForProfile);

  Future<void> pickStartupChannelForProfile() async {
    final choice = await showIptvStartupChannelPicker(_deps.context());
    if (choice == null || !_deps.mounted()) return;
    await StartupIptvStorage.setStartupIptvChannel(
      choice.url,
      name: choice.name,
      playlistId: choice.playlistId,
      channelNumber: choice.channelNumber,
      group: choice.group,
      logoUrl: choice.logoUrl,
      httpHeaders: choice.httpHeaders.isEmpty ? null : choice.httpHeaders,
    );
    final stored = await StartupIptvStorage.getStartupIptvChannel();
    if (_deps.mounted()) {
      _deps.setState(() => _deps.preferencesOwner.startupChannel = stored);
    }
  }

  /// Same persist-then-reflect contract as the root settings screen's
  /// Appearance rows: the picker page owns the write; re-read on the way
  /// back so the hub caption matches.
  Future<void> openIptvStylePicker() async {
    await pushSettingsPage(_deps.context(), const IptvStylePage());
    if (!_deps.mounted()) return;
    final style = await IptvAppearanceStorage.getIptvStyle();
    if (_deps.mounted()) {
      _deps.setState(() => _deps.preferencesOwner.iptvStyle = style);
    }
  }

  Future<void> openPlayerGuidePicker() async {
    await pushSettingsPage(_deps.context(), const PlayerGuideStylePage());
    if (!_deps.mounted()) return;
    final style = await IptvAppearanceStorage.getIptvPlayerGuideStyle();
    if (_deps.mounted()) {
      _deps.setState(() => _deps.preferencesOwner.playerGuideStyle = style);
    }
  }
}
