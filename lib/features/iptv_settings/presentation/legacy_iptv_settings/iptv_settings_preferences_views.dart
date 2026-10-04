import 'package:debrify/features/iptv_settings/presentation/iptv_settings_focusable_tile.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsPreferencesViewsDeps = ({
  IptvSettingsPreferencesOwner preferencesOwner,
  Future<void> Function(bool enabled) setStartupEnabled,
  String Function() lastLiveChannelLabel,
  Future<void> Function(String? mode) setStartupMode,
  String Function() startupChannelLabel,
  IptvSettingsFocusOwner focusOwner,
  Future<void> Function() pickStartupChannel,
  Future<void> Function(bool value) setTrackContinueWatching,
  Future<void> Function(bool value) setChannelPreviewEnabled,
});

class IptvSettingsPreferencesViews {
  IptvSettingsPreferencesViews(this._deps);
  final IptvSettingsPreferencesViewsDeps _deps;

  Widget buildStartupView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsSectionLabel('Startup'),
        const SizedBox(height: 6),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Start on a channel'),
                subtitle: const Text(
                  'Open straight into a live channel when the app starts. '
                  'Press BACK while it is tuning to stop.',
                ),
                value: _deps.preferencesOwner.startupEnabled,
                onChanged: _deps.setStartupEnabled,
              ),
              if (_deps.preferencesOwner.startupEnabled) ...[
                const Divider(height: 1),
                RadioListTile<String>(
                  title: const Text('Last watched channel'),
                  subtitle: Text(
                    _deps.preferencesOwner.lastLiveChannel == null
                        // Honest about the bootstrap: the first boot after
                        // enabling this has nothing to resume, and silently
                        // doing nothing reads as broken.
                        ? 'Nothing watched yet — starts on the first '
                              'channel, then remembers what you watch.'
                        : 'Currently: ${_deps.lastLiveChannelLabel()}',
                  ),
                  value: StartupIptvStorage.startupIptvModeLast,
                  groupValue: _deps.preferencesOwner.startupMode,
                  onChanged: _deps.setStartupMode,
                ),
                RadioListTile<String>(
                  title: const Text('A specific channel'),
                  subtitle: Text(_deps.startupChannelLabel()),
                  value: StartupIptvStorage.startupIptvModePinned,
                  groupValue: _deps.preferencesOwner.startupMode,
                  onChanged: _deps.setStartupMode,
                ),
                if (_deps.preferencesOwner.startupMode ==
                    StartupIptvStorage.startupIptvModePinned)
                  IptvSettingsFocusableTile(
                    focusNode: _deps.focusOwner.startupChannelFocusNode,
                    icon: Icons.live_tv_rounded,
                    label: _deps.preferencesOwner.startupChannel == null
                        ? 'Choose channel'
                        : 'Change channel',
                    onTap: _deps.pickStartupChannel,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget buildContinueWatchingView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsSectionLabel('Continue watching'),
        const SizedBox(height: 6),
        Card(
          child: SwitchListTile(
            title: const Text('Track movies and series'),
            subtitle: const Text(
              'Keeps a Continue watching shelf of the on-demand items you '
              'start, on Home and in IPTV. Off hides it and stops adding to '
              'it — nothing is deleted, and playback still resumes where '
              'you left off.',
            ),
            value: _deps.preferencesOwner.trackContinueWatching,
            onChanged: _deps.setTrackContinueWatching,
          ),
        ),
      ],
    );
  }

  Widget buildChannelPreviewView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsSectionLabel('Channel preview'),
        const SizedBox(height: 6),
        Card(
          child: SwitchListTile(
            title: const Text('Play channel previews'),
            subtitle: const Text(
              'Plays the focused channel in the side panel while you browse. '
              'This opens a provider stream and may count toward your '
              'connection limit. Fullscreen playback still works when off.',
            ),
            value: _deps.preferencesOwner.channelPreviewEnabled,
            onChanged: _deps.setChannelPreviewEnabled,
          ),
        ),
      ],
    );
  }
}
