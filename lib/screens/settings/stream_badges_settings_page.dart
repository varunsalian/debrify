import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/stream_badge_rules.dart';
import '../../services/analytics_service.dart';
import '../../services/stream_badges_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../widgets/stream_badge_strip.dart';
import '../../widgets/text_prompt_dialog.dart';
import 'widgets/settings_widgets.dart';

/// Settings › Play Loader › Stream badges: import Nuvio-style `badges.json`
/// rulesets and manage the imported sources.
class StreamBadgesSettingsPage extends StatefulWidget {
  const StreamBadgesSettingsPage({super.key});

  @override
  State<StreamBadgesSettingsPage> createState() =>
      _StreamBadgesSettingsPageState();
}

class _StreamBadgesSettingsPageState extends State<StreamBadgesSettingsPage> {
  final StreamBadgesService _service = StreamBadgesService.instance;
  final FocusNode _firstTileFocusNode = FocusNode(
    debugLabel: 'stream-badges-first',
  );

  bool _loading = true;
  bool _busy = false;
  bool _enabled = true;
  List<StreamBadgeSource> _sources = const [];

  /// Each source's ruleset, parsed once per [_load] (null when its JSON no
  /// longer parses); the tiles describe every source on every build.
  Map<String, StreamBadgeRuleset?> _rulesets = const {};

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('stream_badges_settings');
    unawaited(_load());
  }

  @override
  void dispose() {
    _firstTileFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _service.warmUp();
    final sources = await _service.getSources();
    final rulesets = {
      for (final s in sources) s.id: StreamBadgeRuleset.tryParse(s.json),
    };
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _rulesets = rulesets;
      _enabled = _service.enabled;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _firstTileFocusNode.context != null) {
        _firstTileFocusNode.requestFocus();
      }
    });
  }

  // ── Import flows ───────────────────────────────────────────────────────

  Future<void> _guarded(Future<void> Function() flow) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await flow();
    } on FormatException catch (e) {
      _showError(messenger, e.message);
    } catch (e) {
      _showError(messenger, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _importFromFile() => _guarded(() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final List<int> bytes;
    if (file.bytes != null) {
      bytes = file.bytes!;
    } else if (file.path != null) {
      bytes = await file.xFile.readAsBytes();
    } else {
      throw const FormatException('Could not read the selected file.');
    }
    if (bytes.length > StreamBadgesService.maxImportBytes) {
      throw const FormatException(
        'That file is too large to be a badges file.',
      );
    }
    final name = file.name.replaceAll(
      RegExp(r'\.json$', caseSensitive: false),
      '',
    );
    await _runImport(
      () => _service.importJson(
        utf8.decode(bytes, allowMalformed: true),
        name: name.isEmpty ? 'Badges' : name,
      ),
    );
  });

  Future<void> _importFromUrl() => _guarded(() async {
    final url = await _prompt(
      title: 'Import from link',
      hint: 'https://raw.githubusercontent.com/…/badges.json',
      helper:
          'A direct link to a badges.json file. Link sources can be '
          'refreshed later.',
      keyboardType: TextInputType.url,
      action: 'Import',
    );
    if (url == null || url.trim().isEmpty || !mounted) return;
    await _runImport(() => _service.importFromUrl(url));
  });

  Future<void> _importFromPaste() => _guarded(() async {
    final text = await _prompt(
      title: 'Paste badges JSON',
      hint: '{ "groups": [ … ], "filters": [ … ] }',
      helper: 'Paste the contents of a badges.json file.',
      multiline: true,
      action: 'Import',
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _runImport(() => _service.importJson(text, name: 'Pasted badges'));
  });

  Future<void> _runImport(
    Future<StreamBadgeImportResult> Function() run,
  ) async {
    setState(() => _busy = true);
    try {
      final result = await run();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      await _showImportResult(result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Per-source actions ─────────────────────────────────────────────────

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    await _service.setEnabled(value);
  }

  Future<void> _openSourceActions(StreamBadgeSource s) async {
    final ruleset = _rulesets[s.id];
    final action = await showDialog<String>(
      context: context,
      builder: (context) => Theme(
        data: settingsPageTheme(context),
        child: AlertDialog(
          title: Text(s.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_describe(s)),
              if (s.url != null) ...[
                const SizedBox(height: 10),
                Text(
                  s.url!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppThemeScope.of(context).settings.dim,
                  ),
                ),
              ],
              if (ruleset != null) ...[
                const SizedBox(height: 14),
                StreamBadgeStrip(
                  badges: ruleset.rules
                      .where((r) => r.enabled)
                      .take(12)
                      .toList(),
                  height: 18,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('delete'),
              child: const Text('Delete'),
            ),
            if (s.url != null)
              TextButton(
                onPressed: () => Navigator.of(context).pop('refresh'),
                child: const Text('Refresh'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('toggle'),
              child: Text(s.enabled ? 'Disable' : 'Enable'),
            ),
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'toggle':
        await _service.setSourceEnabled(s.id, !s.enabled);
        await _load();
      case 'refresh':
        await _guarded(() async {
          await _runImport(() async {
            final r = await _service.refresh(s.id);
            if (r == null) {
              throw const FormatException(
                'This source has no link to refresh.',
              );
            }
            return r;
          });
        });
      case 'delete':
        final confirmed = await _confirm(
          title: 'Delete "${s.name}"?',
          body:
              'Its badges disappear from the source list. Import the file '
              'again to get it back.',
          action: 'Delete',
        );
        if (confirmed && mounted) {
          await _service.remove(s.id);
          await _load();
        }
    }
  }

  Future<void> _removeAll() async {
    if (_sources.isEmpty) return;
    final confirmed = await _confirm(
      title: 'Remove all badge sources?',
      body: 'Every imported ruleset is deleted from this profile.',
      action: 'Remove all',
    );
    if (!confirmed || !mounted) return;
    await _service.clear();
    await _load();
  }

  // ── Dialog helpers ─────────────────────────────────────────────────────

  String _describe(StreamBadgeSource s) {
    final set = _rulesets[s.id];
    if (set == null) return 'Could not read this file';
    final invalid = set.invalidRules.length;
    final parts = [
      '${set.enabledCount} of ${set.rules.length} rule'
          '${set.rules.length == 1 ? '' : 's'} on',
      '${set.groups.length} group${set.groups.length == 1 ? '' : 's'}',
      if (invalid > 0) '$invalid unsupported pattern${invalid == 1 ? '' : 's'}',
      if (!s.enabled) 'disabled',
    ];
    return parts.join(' · ');
  }

  String _subtitle(StreamBadgeSource s) {
    final base = _describe(s);
    return s.url != null ? '$base · link' : base;
  }

  Future<String?> _prompt({
    required String title,
    required String hint,
    required String helper,
    required String action,
    bool multiline = false,
    TextInputType? keyboardType,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => Theme(
        data: settingsPageTheme(context),
        child: TextPromptDialog(
          title: title,
          hint: hint,
          helper: helper,
          action: action,
          multiline: multiline,
          keyboardType: keyboardType,
        ),
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: settingsPageTheme(context),
        child: AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  Future<void> _showImportResult(StreamBadgeImportResult r) {
    final set = r.ruleset;
    final invalid = set.invalidRules;
    final lines = <String>[
      '${set.enabledCount} of ${set.rules.length} rules enabled, '
          '${set.groups.length} groups.',
      if (invalid.isNotEmpty)
        '\n${invalid.length} pattern${invalid.length == 1 ? '' : 's'} could '
            'not be compiled and will not match:\n'
            '${invalid.map((x) => x.name).join(', ')}',
    ];
    return showDialog<void>(
      context: context,
      builder: (context) => Theme(
        data: settingsPageTheme(context),
        child: AlertDialog(
          title: Text(
            r.replaced
                ? 'Updated ${r.source.name}'
                : 'Imported ${r.source.name}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lines.join('\n')),
              const SizedBox(height: 14),
              StreamBadgeStrip(
                badges: set.rules.where((x) => x.enabled).take(12).toList(),
                height: 18,
              ),
            ],
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Stream badges',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsPageScaffold(
      title: 'Stream badges',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.sell_rounded,
                  title: 'Stream badges',
                  subtitle:
                      'Label sources with chips from a Nuvio-style badges.json '
                      '— provider, format, resolution, HDR, audio, language',
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: '',
                  children: [
                    SettingsToggleTile(
                      icon: Icons.sell_rounded,
                      title: 'Show stream badges',
                      subtitle: _sources.isEmpty
                          ? 'Import a badges file below to start'
                          : 'Chips from your imported rulesets on every source',
                      value: _enabled,
                      onChanged: _setEnabled,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsSection(
                  title: 'Import',
                  blurb:
                      'A badges file is a list of regular-expression rules; a '
                      'rule that matches a source\'s name or description adds '
                      'its chip. Files made for Nuvio work as they are.',
                  children: [
                    SettingsTile(
                      icon: Icons.link_rounded,
                      title: 'Import from link',
                      subtitle: _busy
                          ? 'Importing…'
                          : 'Paste a raw badges.json URL (refreshable)',
                      enabled: !_busy,
                      onTap: _importFromUrl,
                      focusNode: _firstTileFocusNode,
                    ),
                    SettingsTile(
                      icon: Icons.upload_file_rounded,
                      title: 'Import from file',
                      subtitle: 'Pick a badges.json on this device',
                      enabled: !_busy,
                      onTap: _importFromFile,
                    ),
                    SettingsTile(
                      icon: Icons.content_paste_rounded,
                      title: 'Paste JSON',
                      subtitle: 'Paste the file contents directly',
                      enabled: !_busy,
                      onTap: _importFromPaste,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsSection(
                  title: 'Your rulesets',
                  blurb: _sources.isEmpty
                      ? 'Nothing imported yet. Rulesets apply in the order '
                            'listed; tap one to refresh, disable or delete it.'
                      : null,
                  children: [
                    for (final s in _sources)
                      SettingsTile(
                        icon: s.enabled
                            ? Icons.sell_rounded
                            : Icons.sell_outlined,
                        title: s.name,
                        subtitle: _subtitle(s),
                        tag: s.url != null ? 'LINK' : null,
                        onTap: () => _openSourceActions(s),
                      ),
                    if (_sources.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No rulesets yet.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                ),
                if (_sources.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SettingsSection(
                    title: 'Danger Zone',
                    children: [
                      SettingsTile(
                        icon: Icons.delete_sweep_rounded,
                        title: 'Remove all rulesets',
                        subtitle: 'Delete every imported badges file',
                        destructive: true,
                        onTap: _removeAll,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
