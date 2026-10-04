import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart';
import 'package:debrify/screens/settings/recordings_page.dart';
import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/widgets/recording_limit_dialogs.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsRecordingActionsDeps = ({
  IptvSettingsRecordingOwner recordingOwner,
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
});

class IptvSettingsRecordingActions {
  IptvSettingsRecordingActions(this._deps);
  final IptvSettingsRecordingActionsDeps _deps;

  Future<void> requestBatteryExemption() async {
    _deps.recordingOwner.recheckBatteryOnResume = true;
    await LiveRecordingService.requestIgnoreBatteryOptimizations();
  }

  Future<void> pickMaxConcurrent() async {
    final picked = await showRecordingLimitPicker(_deps.context());
    if (picked != null && _deps.mounted()) {
      _deps.setState(() => _deps.recordingOwner.maxConcurrent = picked);
    }
  }

  Future<void> openScheduledRecordings() async {
    await Navigator.of(
      _deps.context(),
    ).push(MaterialPageRoute<void>(builder: (_) => const RecordingsPage()));
    // Additions/cancellations on the page change the count shown here.
    final count = DesktopScheduleService.instance.isSupported
        ? (await DesktopScheduleService.instance.list()).length
        : (await LiveRecordingService.listSchedules()).length;
    if (_deps.mounted()) {
      _deps.setState(() => _deps.recordingOwner.scheduledCount = count);
    }
  }
}
