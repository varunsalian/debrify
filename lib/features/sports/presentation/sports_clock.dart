import 'package:debrify/widgets/calendar_display_preferences.dart';
import 'package:flutter/widgets.dart';

/// A local clock time in the board's format.
typedef SportsClock = String Function(DateTime local);

/// The device's 12/24-hour preference, as the tracker calendars show it.
SportsClock sportsClock(BuildContext context) =>
    (local) => CalendarTimeFormat.device.format(context, local);
