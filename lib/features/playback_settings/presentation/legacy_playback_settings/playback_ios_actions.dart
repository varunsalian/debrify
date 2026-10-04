import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_ios_state.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/services/storage/external_player_storage.dart';
import 'package:flutter/material.dart';

typedef PlaybackIosActionsDependencies = ({
  BuildContext Function() context,
  PlaybackIosState ios,
  bool Function() mounted,
  void Function(VoidCallback) setState,
});

class PlaybackIosActions {
  final PlaybackIosActionsDependencies _deps;
  PlaybackIosActions(this._deps);

  // iOS external player settings methods
  Future<void> selectIOSPlayer(iOSExternalPlayer player) async {
    try {
      await ExternalPlayerStorage.setPreferredIOSExternalPlayer(
        player.storageKey,
      );
      _deps.setState(() {
        _deps.ios.selectedIOSPlayer = player;
      });
    } catch (e) {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(
          _deps.context(),
        ).showSnackBar(SnackBar(content: Text('Failed to save setting: $e')));
      }
    }
  }

  Future<void> saveIOSCustomScheme() async {
    final scheme = _deps.ios.iosSchemeController.text.trim();

    final validation = validateCustomScheme(scheme);
    if (!validation.isValid) {
      _deps.setState(() {
        _deps.ios.iosSchemeError = validation.errorMessage;
      });
      return;
    }

    try {
      await ExternalPlayerStorage.setIOSCustomSchemeTemplate(scheme);
      await ExternalPlayerStorage.setPreferredIOSExternalPlayer(
        'custom_scheme',
      );

      _deps.setState(() {
        _deps.ios.iosCustomScheme = scheme;
        _deps.ios.iosSchemeError = null;
        _deps.ios.selectedIOSPlayer = iOSExternalPlayer.customScheme;
      });

      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          const SnackBar(content: Text('Custom URL scheme saved')),
        );
      }
    } catch (e) {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(content: Text('Failed to save URL scheme: $e')),
        );
      }
    }
  }

  Future<void> clearIOSCustomScheme() async {
    try {
      await ExternalPlayerStorage.setIOSCustomSchemeTemplate(null);

      if (_deps.ios.selectedIOSPlayer == iOSExternalPlayer.customScheme) {
        await ExternalPlayerStorage.setPreferredIOSExternalPlayer('vlc');
        _deps.setState(() {
          _deps.ios.selectedIOSPlayer = iOSExternalPlayer.vlc;
        });
      }

      _deps.ios.iosSchemeController.clear();
      _deps.setState(() {
        _deps.ios.iosCustomScheme = null;
        _deps.ios.iosSchemeError = null;
      });
    } catch (e) {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(content: Text('Failed to clear URL scheme: $e')),
        );
      }
    }
  }
}
