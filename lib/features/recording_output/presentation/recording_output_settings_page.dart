// Recording location & timing settings page.
//
// A standalone surface for the device-wide RecordingOutputSettings: where
// recordings are saved and how far the capture window is padded. The page
// takes the platform (and the optional folder picker) from its caller so it
// contains no platform checks of its own; storage goes through
// [RecordingOutputStoreApi] so tests can substitute a fake store.

import 'package:flutter/material.dart';

import '../data/recording_output_store.dart';
import '../models/recording_output_settings.dart';
import 'network_share_settings_page.dart';

/// The persistence the page needs. Tests pass a fake; production uses the
/// private default that delegates to [RecordingOutputStore].
abstract interface class RecordingOutputStoreApi {
  Future<RecordingOutputSettings> read();
  Future<void> write(RecordingOutputSettings s);
}

/// Result of the folder picker: null means cancelled, otherwise the chosen
/// folder (a SAF tree on Android, a directory path on desktop).
typedef RecordingFolderPick =
    Future<({String? treeUri, String? displayName, String? path})?> Function();

/// Plain [StatefulWidget] entry point: push it with a route like any other
/// page; the AppBar back button closes it.
class RecordingOutputSettingsPage extends StatefulWidget {
  const RecordingOutputSettingsPage({
    super.key,
    required this.platform,
    this.folderPicker,
    this.store,
  });

  final RecordingPlatform platform;

  /// Null hides the "Save recordings to" row entirely.
  final RecordingFolderPick? folderPicker;

  /// Defaults to the shared [RecordingOutputStore].
  final RecordingOutputStoreApi? store;

  @override
  State<RecordingOutputSettingsPage> createState() =>
      _RecordingOutputSettingsPageState();
}

class _RecordingOutputSettingsPageState
    extends State<RecordingOutputSettingsPage> {
  RecordingOutputStoreApi get _store =>
      widget.store ?? const _RecordingOutputStoreBridge();

  RecordingOutputSettings? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _store.read();
    if (mounted) setState(() => _settings = settings);
  }

  Future<void> _save(RecordingOutputSettings next) async {
    setState(() => _settings = next);
    await _store.write(next);
    if (mounted) setState(() {});
  }

  Future<void> _pickFolder() async {
    final picker = widget.folderPicker!;
    final current = _settings ?? const RecordingOutputSettings();
    final pick = await picker();
    if (pick == null || !mounted) return;
    final displayName = pick.displayName;
    final path = pick.path;
    await _save(
      current.copyWith(
        treeUri: pick.treeUri,
        treeDisplayName: displayName == null || displayName.isEmpty
            ? (path == null || path.isEmpty ? 'Chosen folder' : path)
            : displayName,
        directoryPath: path,
      ),
    );
  }

  Future<void> _chooseStartPad(int minutes) async {
    final current = _settings ?? const RecordingOutputSettings();
    await _save(current.copyWith(startPadMinutes: minutes));
  }

  Future<void> _chooseEndPad(int minutes) async {
    final current = _settings ?? const RecordingOutputSettings();
    await _save(current.copyWith(endPadMinutes: minutes));
  }

  String _padText(int? minutes) => minutes == null ? 'Off' : '$minutes min';

  String get _endPadDefaultText {
    final defaultMinutes = widget.platform == RecordingPlatform.android ? 2 : 0;
    return '${_padText(defaultMinutes)} (default)';
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final showFolderRow = widget.folderPicker != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Recording location & timing')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (showFolderRow)
                  _card(
                    children: [
                      _settingsRow(
                        title: 'Save recordings to',
                        subtitle: recordingLocationLabel(settings),
                        showChevron: true,
                        autofocus: true,
                        onTap: _pickFolder,
                      ),
                      if (settings.hasCustomFolder)
                        _settingsRow(
                          title: 'Use default folder',
                          onTap: () =>
                              _save(settings.copyWith(clearFolder: true)),
                        ),
                    ],
                  ),
                _card(
                  children: [
                    _settingsRow(
                      title: 'Start recording early',
                      subtitle: _padText(settings.startPadMinutes),
                      showChevron: true,
                      autofocus: !showFolderRow,
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (dialogContext) => SimpleDialog(
                          title: const Text('Start recording early'),
                          children: [
                            for (final minutes
                                in RecordingOutputSettings.startPadChoices)
                              SimpleDialogOption(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  _chooseStartPad(minutes);
                                },
                                child: Text(_padText(minutes)),
                              ),
                          ],
                        ),
                      ),
                    ),
                    _settingsRow(
                      title: 'Keep recording after the end',
                      subtitle: settings.endPadMinutes == null
                          ? _endPadDefaultText
                          : _padText(settings.endPadMinutes),
                      showChevron: true,
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (dialogContext) => SimpleDialog(
                          title: const Text('Keep recording after the end'),
                          children: [
                            for (final minutes
                                in RecordingOutputSettings.endPadChoices)
                              SimpleDialogOption(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  _chooseEndPad(minutes);
                                },
                                child: Text(_padText(minutes)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // Both platforms this page exists for (Android and desktop)
                // have recordings, so the entry has no platform guard of its
                // own; RecordingPlatform has no other value.
                _card(
                  children: [
                    _settingsRow(
                      title: 'Network share (SMB)',
                      subtitle: 'Record to a NAS or another computer',
                      showChevron: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const NetworkShareSettingsPage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _settingsRow({
    required String title,
    String? subtitle,
    bool showChevron = false,
    bool autofocus = false,
    VoidCallback? onTap,
  }) {
    return ListTile(
      key: ValueKey(title),
      autofocus: autofocus,
      enabled: onTap != null,
      minVerticalPadding: 16,
      trailing: showChevron ? const Icon(Icons.chevron_right, size: 22) : null,
      onTap: onTap,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
    );
  }
}

/// Production store: the shared [RecordingOutputStore] statics.
class _RecordingOutputStoreBridge implements RecordingOutputStoreApi {
  const _RecordingOutputStoreBridge();

  @override
  Future<RecordingOutputSettings> read() => RecordingOutputStore.read();

  @override
  Future<void> write(RecordingOutputSettings s) =>
      RecordingOutputStore.write(s);
}
