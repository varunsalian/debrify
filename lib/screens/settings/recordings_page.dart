import 'dart:async';

import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_data.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_dependencies.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_sections.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:flutter/material.dart';

import 'recording_output_route.dart';

// The DVR's front door — three zones on one page:
//   RECORDING NOW  live captures with a Stop button each
//   SCHEDULED      upcoming recordings + the manual channel/time/duration flow
//   LIBRARY        every finished recording, playable in-app with one press
//
// Styled with the IPTV cockpit's tokens (this page belongs to the DVR world,
// not settings-Material). One 1s wall-clock notifier drives elapsed timers and
// countdown chips through scoped ValueListenableBuilders — never a whole-page
// rebuild per second — and it only runs while something is live or scheduled.

class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage>
    with WidgetsBindingObserver {
  final _owners = RecordingsHubOwners();
  RecordingsHubSections? _composition;
  RecordingsHubSections get _sections => _composition ??= RecordingsHubSections(
    RecordingsHubDependencies(
      owners: _owners,
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      sections: () => _sections,
      openOutputSettings: recordingOutputSettingsAvailable
          ? () => openRecordingOutputSettings(context)
          : null,
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LiveRecordingService.schedulesRevision.addListener(_onRevision);
    if (_sections.data.desktop) {
      DesktopRecordingService.instance.revision.addListener(_onRevision);
    }
    unawaited(_sections.data.loadAll());
    unawaited(
      DevicePreferences.instance().then((prefs) {
        if (!mounted) return;
        final at =
            prefs.getInt(RecordingsHubData.batteryNudgeDismissedPref) ?? 0;
        if (at != 0) setState(() => _owners.batteryNudgeDismissedAtMs = at);
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LiveRecordingService.schedulesRevision.removeListener(_onRevision);
    if (_sections.data.desktop) {
      DesktopRecordingService.instance.revision.removeListener(_onRevision);
    }
    _owners.ticker?.cancel();
    _owners.poll?.cancel();
    _owners.now.dispose();
    _owners.firstLibraryFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _owners.appVisible = true;
      // _loadAll re-arms the ticker and poll via _syncTimers.
      unawaited(_sections.data.loadAll());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Nothing here is visible while the app isn't — on TV that includes
      // the whole time the native player plays a recording over Flutter, so
      // the 1s clock and the 3s native poll must not keep burning under it.
      _owners.appVisible = false;
      _owners.ticker?.cancel();
      _owners.ticker = null;
      _owners.poll?.cancel();
      _owners.poll = null;
    }
  }

  void _onRevision() {
    if (mounted) unawaited(_sections.data.loadAll());
  }

  @override
  Widget build(BuildContext context) => _sections.layout.build(context);
}
