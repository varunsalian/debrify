// Keeps kick-off reminders live for the whole app session.
//
// Presentation layer, composition only. Listening keeps the reminders
// notifier active, so a profile switch rebuilds it at once: the device's
// alerts then follow the active profile even if the board is never opened.
import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SportsReminderHost extends ConsumerWidget {
  const SportsReminderHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.read(sportsReminderSchedulerProvider).isSupported) {
      ref.listen(sportsRemindersProvider, (_, _) {});
    }
    return child;
  }
}
