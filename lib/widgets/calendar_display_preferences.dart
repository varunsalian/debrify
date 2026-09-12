import 'package:flutter/material.dart';

/// Shared by every tracker calendar and its episode sheet.
enum CalendarTimeFormat {
  device('Device default'),
  twelveHour('12-hour'),
  twentyFourHour('24-hour');

  const CalendarTimeFormat(this.label);
  final String label;

  String format(BuildContext context, DateTime local) {
    final minute = local.minute.toString().padLeft(2, '0');
    return switch (this) {
      device => MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(local),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      ),
      twelveHour =>
        '${local.hour % 12 == 0 ? 12 : local.hour % 12}:$minute ${local.hour < 12 ? 'AM' : 'PM'}',
      twentyFourHour => '${local.hour.toString().padLeft(2, '0')}:$minute',
    };
  }
}

class CalendarTimeFormatScope extends InheritedWidget {
  const CalendarTimeFormatScope({
    super.key,
    required this.format,
    required super.child,
  });

  final CalendarTimeFormat format;

  static String formatTime(BuildContext context, DateTime local) =>
      (context
                  .dependOnInheritedWidgetOfExactType<CalendarTimeFormatScope>()
                  ?.format ??
              CalendarTimeFormat.device)
          .format(context, local);

  @override
  bool updateShouldNotify(CalendarTimeFormatScope oldWidget) =>
      format != oldWidget.format;
}

/// Historical and future months remain fully browsable. In the current month,
/// include all of today, even episodes whose air time has already passed.
bool calendarIncludesDay(
  DateTime day,
  DateTime now, {
  required bool showEarlier,
}) =>
    showEarlier ||
    day.year != now.year ||
    day.month != now.month ||
    day.day >= now.day;
