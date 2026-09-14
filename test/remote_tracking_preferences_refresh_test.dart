import 'dart:convert';
import 'package:debrify/services/hide_watched_prefs.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/remote_control/remote_command_router.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'direct remote tracking push refreshes Home after updating the cache',
    () async {
      SharedPreferences.setMockInitialValues({});
      await HideWatchedPrefs.setEnabled(false);
      final observed = <bool>[];
      void refreshed() => observed.add(HideWatchedPrefs.enabled);
      MainPageBridge.addHomeSettingsListener(refreshed);
      addTearDown(() {
        MainPageBridge.removeHomeSettingsListener(refreshed);
        RemoteCommandRouter().clearProfileSessionState();
      });
      await RemoteCommandRouter().receiveTransferCommand(
        RemoteAction.config,
        ConfigCommand.trackingPreferences,
        jsonEncode({'hide_watched': true}),
        const RemoteCommandContext(encrypted: true, authorized: true),
      );
      expect(observed, [true]);
    },
  );
}
