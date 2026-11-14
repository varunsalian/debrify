// Platform adapter for kick-off reminders: Android exact alarms and iOS local
// notifications behind one method channel (see SportsReminders.kt and
// SportsReminderBridge.swift). Feature-agnostic: it moves plain maps.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

const _channel = MethodChannel('com.debrify.app/sports_reminders');

/// Asks for notification permission if needed; true when alerts will show.
/// Android goes through permission_handler; iOS asks natively, because
/// permission_handler's iOS notification support is compiled out here.
Future<bool> ensureReminderNotificationPermission() async {
  if (Platform.isAndroid) {
    if ((await Permission.notification.status).isGranted) return true;
    return (await Permission.notification.request()).isGranted;
  }
  return await _channel.invokeMethod<bool>('requestPermission') ?? false;
}

/// Makes [alerts] (`id`, `fireAtMs`, `title`, `body`) the complete set of
/// scheduled reminders.
Future<void> replaceScheduledReminders(List<Map<String, Object>> alerts) =>
    _channel.invokeMethod<void>('replaceAll', {'alerts': alerts});
