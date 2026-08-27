import 'package:flutter/material.dart';

import '../../models/tracking_source.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../services/simkl/simkl_service.dart';
import '../../services/storage_service.dart';
import '../../services/trakt/trakt_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';

class TrackingSettingsPage extends StatefulWidget {
  const TrackingSettingsPage({super.key});

  @override
  State<TrackingSettingsPage> createState() => _TrackingSettingsPageState();
}

class _TrackingSettingsPageState extends State<TrackingSettingsPage> {
  bool _loading = true;
  Set<TrackingSource> _scrobble = {TrackingSource.local};
  WatchProgressSource _progress = WatchProgressSource.smart;
  Set<TrackingSource> _ticks = Set<TrackingSource>.of(TrackingSource.values);
  Set<TrackingSource> _connected = {};
  int _selectedSection = 0;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('tracking_settings');
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<Object>([
      StorageService.getTrackingScrobbleTargets(),
      StorageService.getWatchProgressSource(),
      StorageService.getHomeTickSources(),
      TraktService.instance.isAuthenticated(),
      SimklService.instance.isAuthenticated(),
      MdblistService.instance.isAuthenticated(),
      StorageService.takeTrackingProgressFallbackNotice(),
    ]);
    if (!mounted) return;
    final connected = <TrackingSource>{
      if (values[3] as bool) TrackingSource.trakt,
      if (values[4] as bool) TrackingSource.simkl,
      if (values[5] as bool) TrackingSource.mdblist,
    };
    var progress = values[1] as WatchProgressSource;
    final dedicated = _trackingSourceForProgress(progress);
    var fellBack = false;
    if (dedicated != null &&
        dedicated != TrackingSource.local &&
        !connected.contains(dedicated)) {
      progress = WatchProgressSource.smart;
      await StorageService.setWatchProgressSource(progress);
      fellBack = true;
    }
    if (!mounted) return;
    setState(() {
      _scrobble = Set<TrackingSource>.of(values[0] as Set<TrackingSource>);
      _progress = progress;
      _ticks = Set<TrackingSource>.of(values[2] as Set<TrackingSource>);
      _connected = connected;
      _loading = false;
    });
    if (fellBack || values[6] as bool) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your selected progress tracker is disconnected. Using Smart.',
          ),
        ),
      );
    }
  }

  TrackingSource? _trackingSourceForProgress(WatchProgressSource source) =>
      switch (source) {
        WatchProgressSource.smart => null,
        WatchProgressSource.local => TrackingSource.local,
        WatchProgressSource.trakt => TrackingSource.trakt,
        WatchProgressSource.simkl => TrackingSource.simkl,
        WatchProgressSource.mdblist => TrackingSource.mdblist,
      };

  String _label(TrackingSource source) => switch (source) {
    TrackingSource.local => 'This device',
    TrackingSource.trakt => 'Trakt',
    TrackingSource.simkl => 'Simkl',
    TrackingSource.mdblist => 'MDBList',
  };

  String _progressLabel(WatchProgressSource source) => switch (source) {
    WatchProgressSource.smart => 'Smart',
    WatchProgressSource.local => 'This device',
    WatchProgressSource.trakt => 'Trakt',
    WatchProgressSource.simkl => 'Simkl',
    WatchProgressSource.mdblist => 'MDBList',
  };

  bool _available(TrackingSource source) =>
      source == TrackingSource.local || _connected.contains(source);

  Future<void> _setScrobble(TrackingSource source, bool enabled) async {
    final next = Set<TrackingSource>.of(_scrobble);
    enabled ? next.add(source) : next.remove(source);
    next.add(TrackingSource.local);
    setState(() => _scrobble = next);
    await StorageService.setTrackingScrobbleTargets(next);
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _setProgress(WatchProgressSource? source) async {
    if (source == null) return;
    setState(() => _progress = source);
    await StorageService.setWatchProgressSource(source);
    MainPageBridge.notifyHomeSettingsChanged();
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _setTick(TrackingSource source, bool enabled) async {
    final next = Set<TrackingSource>.of(_ticks);
    enabled ? next.add(source) : next.remove(source);
    setState(() => _ticks = next);
    await StorageService.setHomeTickSources(next);
    MainPageBridge.notifyHomeSettingsChanged();
  }

  Widget _scrobbleSection() => SettingsSection(
    title: 'Scrobble',
    blurb:
        'Which services record what you watch. Debrify always keeps its own progress.',
    children: [
      for (final source in TrackingSource.values)
        CheckboxListTile(
          value: _scrobble.contains(source),
          onChanged: source == TrackingSource.local || !_available(source)
              ? null
              : (value) => _setScrobble(source, value ?? false),
          title: Text(_label(source)),
          subtitle: source == TrackingSource.local
              ? const Text('Always on')
              : !_available(source)
              ? const Text('Connect this tracker to enable it')
              : null,
          secondary: const Icon(Icons.sync_alt_rounded),
        ),
    ],
  );

  Widget _progressSection() => SettingsSection(
    title: 'Progress source',
    blurb:
        'Controls resume, episode-list progress and ✓ ticks, and which Continue Watching rows are eligible on Home.',
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: DropdownButtonFormField<WatchProgressSource>(
          initialValue: _progress,
          decoration: const InputDecoration(
            labelText: 'Progress source',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final source in WatchProgressSource.values)
              if (source == WatchProgressSource.smart ||
                  _available(_trackingSourceForProgress(source)!))
                DropdownMenuItem(
                  value: source,
                  child: Text(_progressLabel(source)),
                ),
          ],
          onChanged: _setProgress,
        ),
      ),
      ListTile(
        title: Text(switch (_progress) {
          WatchProgressSource.smart =>
            'Combines this device with connected trackers; the most recent activity wins.',
          WatchProgressSource.local =>
            'Resume and Continue Watching use only this device and your watched-at setting. Tracker rows are hidden on Home; history is still sent to ticked services.',
          _ =>
            '${_progressLabel(_progress)} owns your progress. Shows leave Continue Watching by ${_progressLabel(_progress)}\'s rules.',
        }),
        subtitle: _progress == WatchProgressSource.local
            ? const Text("Progress won't follow you to other devices.")
            : null,
      ),
    ],
  );

  Widget _ticksSection() => SettingsSection(
    title: 'Home tick marks',
    blurb:
        'Which histories draw the ✓ on Home cards. Episode lists follow your Progress source.',
    children: [
      for (final source in TrackingSource.values)
        CheckboxListTile(
          value: _ticks.contains(source),
          onChanged: !_available(source)
              ? null
              : (value) => _setTick(source, value ?? false),
          title: Text(_label(source)),
          subtitle: !_available(source)
              ? const Text('Tracker is not connected')
              : null,
          secondary: const Icon(Icons.check_circle_outline),
        ),
    ],
  );

  Widget _mobileBody() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _scrobbleSection(),
      const SizedBox(height: 18),
      _progressSection(),
      const SizedBox(height: 18),
      _ticksSection(),
      const SizedBox(height: 24),
    ],
  );

  Widget _tvBody() {
    const labels = ['Scrobble', 'Progress source', 'Home tick marks'];
    const icons = [
      Icons.sync_alt_rounded,
      Icons.play_circle_outline_rounded,
      Icons.check_circle_outline_rounded,
    ];
    final selected = switch (_selectedSection) {
      0 => _scrobbleSection(),
      1 => _progressSection(),
      _ => _ticksSection(),
    };
    return Row(
      children: [
        SizedBox(
          width: 280,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
            itemCount: labels.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                autofocus: index == 0,
                selected: index == _selectedSection,
                leading: Icon(icons[index]),
                title: Text(labels[index]),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => setState(() => _selectedSection = index),
              ),
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 20, 36, 28),
            children: [selected],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tracking')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : PlatformUtil.isTelevision
          ? _tvBody()
          : _mobileBody(),
    );
  }
}
