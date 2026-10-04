import 'package:debrify/features/iptv_settings/presentation/iptv_settings_focusable_tile.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsRecordingViewDeps = ({
  IptvSettingsRecordingOwner recordingOwner,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  IptvSettingsFocusOwner focusOwner,
  Future<void> Function() pickMaxConcurrent,
  Future<void> Function() requestBatteryExemption,
  Future<void> Function() openScheduledRecordings,
});

class IptvSettingsRecordingView {
  IptvSettingsRecordingView(this._deps);
  final IptvSettingsRecordingViewDeps _deps;

  // The Appearance and Player guide looks are NOT sub-views: their hub rows
  // push the same standalone picker pages the root Appearance section uses,
  // so each pref keeps exactly one narrow-layout picker implementation.

  // Gated by the hub row (engine support / desktop scheduler), so this view
  // never renders where recording can't run.
  Widget buildRecordingView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsSectionLabel('Recording'),
        const SizedBox(height: 6),
        Card(
          child: Column(
            children: [
              if (_deps.recordingOwner.engineToggleVisible)
                SwitchListTile(
                  title: const Text('Background recording engine'),
                  subtitle: const Text(
                    'Recordings keep running when you zap or leave the '
                    'app, and programmes can be scheduled from the TV '
                    'guide. Off returns to player-tied recording. Uses an '
                    'extra connection to your provider.',
                  ),
                  value: _deps.recordingOwner.recordingEngineOn,
                  onChanged: (enabled) async {
                    await LiveRecordingService.setEngineEnabled(enabled);
                    if (_deps.mounted()) {
                      _deps.setState(
                        () => _deps.recordingOwner.recordingEngineOn = enabled,
                      );
                    }
                  },
                ),
              if (!_deps.recordingOwner.engineToggleVisible ||
                  _deps.recordingOwner.recordingEngineOn) ...[
                if (_deps.recordingOwner.engineToggleVisible)
                  const Divider(height: 1),
                IptvSettingsFocusableTile(
                  focusNode: _deps.focusOwner.maxConcurrentFocusNode,
                  icon: Icons.filter_none_rounded,
                  label:
                      'Simultaneous recordings (${_deps.recordingOwner.maxConcurrent})',
                  onTap: _deps.pickMaxConcurrent,
                ),
                if (_deps.recordingOwner.batteryExempt != null) ...[
                  const Divider(height: 1),
                  IptvSettingsFocusableTile(
                    focusNode: _deps.focusOwner.batteryFocusNode,
                    icon: Icons.battery_alert_rounded,
                    label: _deps.recordingOwner.batteryExempt == true
                        ? 'Battery optimization — excluded ✓'
                        : 'Battery optimization — tap to exclude',
                    onTap: _deps.requestBatteryExemption,
                  ),
                ],
                const Divider(height: 1),
                IptvSettingsFocusableTile(
                  focusNode: _deps.focusOwner.scheduledRecordingsFocusNode,
                  icon: Icons.fiber_manual_record_rounded,
                  label: _deps.recordingOwner.scheduledCount == 0
                      ? 'Recordings'
                      : 'Recordings (${_deps.recordingOwner.scheduledCount} scheduled)',
                  onTap: _deps.openScheduledRecordings,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
