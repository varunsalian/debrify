import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_values_state.dart';
import 'package:debrify/screens/settings/debrify_tv_player_style_page.dart';
import 'package:debrify/screens/settings/play_loader_style_page.dart';
import 'package:debrify/screens/settings/player_dock_page.dart';
import 'package:debrify/screens/settings/player_guide_style_page.dart';
import 'package:debrify/screens/settings/tv_player_controls_style_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

typedef PlaybackPlayerAppearanceDependencies = ({
  BuildContext Function() context,
  PlaybackValuesState values,
});

class PlaybackPlayerAppearance {
  final PlaybackPlayerAppearanceDependencies _deps;
  PlaybackPlayerAppearance(this._deps);

  Widget playerAppearance() => SettingsSection(
    title: 'Appearance',
    blurb: 'The same player styles available in Appearance settings.',
    children: [
      // Match Appearance: Apple TV uses TV controls, not the player dock.
      if (_deps.values.isAndroidTv || !PlatformUtil.isTelevision)
        SettingsTile.spec(
          SettingsRows.playerDock,
          subtitle: _deps.values.isAndroidTv
              ? 'Control style'
              : 'Style, colour and size',
          onTap: () async {
            await pushSettingsPage(
              _deps.context(),
              _deps.values.isAndroidTv
                  ? const TvPlayerControlsStylePage()
                  : const PlayerDockPage(),
            );
          },
        ),
      if (_deps.values.isAndroidTv)
        SettingsTile.spec(
          SettingsRows.debrifyTvPlayer,
          subtitle: 'Debrify TV playback-screen style',
          onTap: () async {
            await pushSettingsPage(
              _deps.context(),
              const DebrifyTvPlayerStylePage(),
            );
          },
        ),
      SettingsTile.spec(
        SettingsRows.playerGuideStyle,
        subtitle: 'In-player IPTV guide style',
        onTap: () async {
          await pushSettingsPage(_deps.context(), const PlayerGuideStylePage());
        },
      ),
      SettingsTile.spec(
        SettingsRows.playLoaderStyle,
        subtitle: 'Playback loading-screen style',
        onTap: () async {
          await pushSettingsPage(_deps.context(), const PlayLoaderStylePage());
        },
      ),
    ],
  );
}
