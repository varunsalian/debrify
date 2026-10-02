import 'package:debrify/features/settings/presentation/legacy_settings/settings_connections.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_summaries.dart';
import 'package:flutter_test/flutter_test.dart';

SettingsConnections connectionViews(
  SettingsSummaries summaries, {
  Future<void> Function()? onTap,
}) {
  final action = onTap ?? () async {};
  return SettingsConnections(summaries, (
    openAllDebridSettings: action,
    openIndexerManagersSettings: action,
    openIptvSettings: action,
    openMdblistSettings: action,
    openMediaServerSettings: action,
    openPikPakSettings: action,
    openPremiumizeSettings: action,
    openRealDebridSettings: action,
    openSimklSettings: action,
    openTorboxSettings: action,
    openTrackingSettings: action,
    openTraktSettings: action,
    openWebDavSettings: action,
  ));
}

void main() {
  test(
    'connection views reread summaries and preserve the action tear-off',
    () async {
      final summaries = SettingsSummaries();
      var opens = 0;
      Future<void> open() async => opens++;
      final connections = connectionViews(summaries, onTap: open);
      final before = connections.rdInfo;

      summaries.realDebridConnected = true;
      summaries.realDebridStatus = 'Connected';
      summaries.realDebridCaption = 'Premium account';
      final after = connections.rdInfo;
      expect(after.connected, isTrue);
      expect(after.status, 'Connected');
      expect(after.caption, 'Premium account');
      expect(before.connected, isFalse);
      expect(before.caption, 'Tap to connect');
      expect(after.onTap, same(before.onTap));
      await after.onTap();
      expect(opens, 1);

      summaries.summaryFailures.add('Real Debrid');
      expect(connections.rdInfo.connected, isFalse);
      expect(connections.rdInfo.status, 'Attention');
      expect(
        connections.rdInfo.caption,
        'Unable to load; open the item to retry',
      );
      summaries.summaryUnavailable.add('Real Debrid');
      expect(connections.rdInfo.caption, 'Unavailable; retry or sign in');
      await connections.rdInfo.onTap();
      expect(opens, 2);
    },
  );

  test(
    'IPTV pending credentials and denial keep their original precedence',
    () {
      final summaries = SettingsSummaries();
      final connections = connectionViews(summaries);
      summaries.iptvCredentialsPending = true;
      expect(connections.iptvInfo.connected, isTrue);
      expect(connections.iptvInfo.status, 'Attention');
      expect(connections.iptvInfo.caption, 'credentials pending owner sign-in');

      summaries.summaryFailures.add('IPTV');
      summaries.summaryUnavailable.add('IPTV');
      expect(connections.iptvInfo.connected, isFalse);
      expect(connections.iptvInfo.caption, 'Unavailable; retry or sign in');
      summaries.summaryFailures.clear();
      expect(connections.iptvInfo.caption, 'credentials pending owner sign-in');
    },
  );
}
