import 'dart:io';

import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';

typedef PlaybackExternalSectionDependencies = ({
  PlaybackCoreState core,
  List<Widget> Function() iosSettings,
  List<Widget> Function() linuxSettings,
  List<Widget> Function() macSettings,
  List<Widget> Function() vrSettings,
  List<Widget> Function() windowsSettings,
});

class PlaybackExternalSection {
  final PlaybackExternalSectionDependencies _deps;
  PlaybackExternalSection(this._deps);
  List<Widget> externalPlayerSettings() {
    return [
      // Android External Player info
      if (Platform.isAndroid && _deps.core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        SettingsInfoBanner(
          text:
              'When enabled, you will be able to choose which app to use when opening videos. Install VLC, MX Player, or other video player apps to see them in the chooser.',
        ),
      ],
      ..._deps.iosSettings(),
      ..._deps.linuxSettings(),
      ..._deps.windowsSettings(),
      ..._deps.macSettings(),
      ..._deps.vrSettings(),
    ];
  }
}
