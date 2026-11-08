// The production [SportsReminderScheduler]: phones and tablets on Android and
// iOS, through the core reminder channel.
//
// Data layer, platform adapter: decides where reminders exist and hands the
// planned alerts to the platform. TVs are excluded: Android TV and tvOS do
// not show app notifications.
import 'dart:io';

import 'package:debrify/core/platform/sports_reminder_channel.dart';
import 'package:debrify/features/sports/models/sports_reminder.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart';

final class PlatformSportsReminderScheduler implements SportsReminderScheduler {
  const PlatformSportsReminderScheduler();

  @override
  bool get isSupported =>
      !kIsWeb &&
      ((Platform.isAndroid && !PlatformUtil.isAndroidTvCached) ||
          PlatformUtil.isIosMobile);

  @override
  Future<bool> ensurePermission() async =>
      isSupported && await ensureReminderNotificationPermission();

  @override
  Future<void> replaceAll(List<SportsReminderAlert> alerts) async {
    if (!isSupported) return;
    await replaceScheduledReminders([
      for (final alert in alerts) alert.toMap(),
    ]);
  }
}
