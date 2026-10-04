import 'dart:io';

import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

typedef PlaybackSettingsLayoutDependencies = ({
  List<Widget> Function() audioSettings,
  PlaybackCoreState core,
  Future<void> Function() openPlayerSettings,
  List<Widget> Function() playerSettings,
  PlaybackSettingsSection Function() section,
  List<Widget> Function() subtitleSettings,
  List<Widget> Function() videoSettings,
});

class PlaybackSettingsLayout {
  final PlaybackSettingsLayoutDependencies _deps;
  PlaybackSettingsLayout(this._deps);

  Widget build(BuildContext context) {
    final section = _deps.section();
    final isSupportedPlatform =
        Platform.isMacOS ||
        Platform.isAndroid ||
        PlatformUtil.isIosMobile ||
        PlatformUtil.isTvOS ||
        Platform.isLinux ||
        Platform.isWindows;
    if (!isSupportedPlatform) {
      return SettingsPageScaffold(
        title: section.label,
        body: const Center(
          child: Text('Player settings are not available on this platform'),
        ),
      );
    }
    if (_deps.core.loading) {
      return SettingsPageScaffold(
        title: section.label,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final managedExternally =
        section != PlaybackSettingsSection.player &&
        _deps.core.defaultPlayerMode != 'debrify';
    return SettingsPageScaffold(
      title: section.label,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Focus(
              focusNode: _deps.core.contentFocusNode,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsPageHeader(
                    icon: section.icon,
                    title: section.label,
                    subtitle: section.description,
                  ),
                  const SizedBox(height: 16),
                  if (managedExternally) ...[
                    SettingsInfoBanner(
                      text:
                          '${_deps.core.defaultPlayerMode == 'deovr' ? 'DeoVR' : 'Your external player'} manages these settings. Choose Debrify Player to configure its defaults.',
                    ),
                    const SizedBox(height: 16),
                    SettingsSection(
                      title: '',
                      children: [
                        SettingsTile(
                          icon: Icons.play_circle_outline_rounded,
                          title: 'Choose player',
                          subtitle: 'Open Player settings',
                          onTap: _deps.openPlayerSettings,
                        ),
                      ],
                    ),
                  ] else
                    ...switch (section) {
                      PlaybackSettingsSection.player => _deps.playerSettings(),
                      PlaybackSettingsSection.video => _deps.videoSettings(),
                      PlaybackSettingsSection.audio => _deps.audioSettings(),
                      PlaybackSettingsSection.subtitles =>
                        _deps.subtitleSettings(),
                    },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
