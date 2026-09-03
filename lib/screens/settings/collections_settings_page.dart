import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/home_collection.dart';
import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/home_collections_store.dart';
import '../../services/main_page_bridge.dart';
import '../../services/stremio_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../widgets/text_prompt_dialog.dart';
import 'widgets/settings_widgets.dart';

/// Settings › Home Screen › Collections: import Nuvio / Xperience-style
/// collection JSON files and manage what has been imported.
///
/// This page owns the data (import, enable/disable, delete); showing and
/// arranging the resulting Home rows is the Home Rows manager's job.
class CollectionsSettingsPage extends StatefulWidget {
  const CollectionsSettingsPage({super.key});

  @override
  State<CollectionsSettingsPage> createState() =>
      _CollectionsSettingsPageState();
}

class _CollectionsSettingsPageState extends State<CollectionsSettingsPage> {
  final HomeCollectionsStore _store = HomeCollectionsStore.instance;
  final FocusNode _firstTileFocusNode = FocusNode(
    debugLabel: 'collections-first',
  );

  bool _loading = true;
  bool _busy = false;
  List<HomeCollection> _collections = const [];
  List<StremioAddon> _addons = const [];
  CollectionFolderLayout _layout = CollectionFolderLayout.rows;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('collections_settings');
    unawaited(_load());
  }

  @override
  void dispose() {
    _firstTileFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final collections = await _store.getCollections();
    final layout = await _store.getFolderLayout();
    List<StremioAddon> addons = const [];
    try {
      addons = await StremioService.instance.getCatalogAddons();
    } catch (_) {
      // Addons only feed the "missing addon" hints; the page works without.
    }
    if (!mounted) return;
    setState(() {
      _collections = collections;
      _addons = addons;
      _layout = layout;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _firstTileFocusNode.context != null) {
        _firstTileFocusNode.requestFocus();
      }
    });
  }

  // ── Import paths ───────────────────────────────────────────────────────

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
    if (bytes.length > HomeCollectionsStore.maxImportBytes) {
      throw const FormatException('That file is too large to be a collection.');
    }
    await _runImport(
      () => _store.importJson(
        utf8.decode(bytes, allowMalformed: true),
        installedAddons: _addons,
      ),
    );
  });

  Future<void> _importFromUrl() => _guarded(() async {
    final url = await _prompt(
      title: 'Import from link',
      hint: 'https://…/collections.json',
      helper: 'A direct link to a collections JSON file.',
      keyboardType: TextInputType.url,
      action: 'Import',
    );
    if (url == null || url.trim().isEmpty || !mounted) return;
    await _runImport(() => _store.importFromUrl(url, installedAddons: _addons));
  });

  Future<void> _importFromPaste() => _guarded(() async {
    final text = await _prompt(
      title: 'Paste collection JSON',
      hint: '[ { "title": "Streaming", "folders": [ … ] } ]',
      helper: 'Paste the contents of a collections JSON file.',
      multiline: true,
      action: 'Import',
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _runImport(() => _store.importJson(text, installedAddons: _addons));
  });

  /// Runs an import flow unless one is already in progress, surfacing any
  /// failure as a snackbar ([FormatException]s carry user-readable text).
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

  Future<void> _runImport(
    Future<HomeCollectionImportResult> Function() run,
  ) async {
    setState(() => _busy = true);
    try {
      final result = await run();
      if (!mounted) return;
      MainPageBridge.notifyHomeSettingsChanged();
      await _load();
      if (!mounted) return;
      await _showImportResult(result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setTabbed(bool tabbed) async {
    final layout = tabbed
        ? CollectionFolderLayout.tabs
        : CollectionFolderLayout.rows;
    setState(() => _layout = layout);
    await _store.setFolderLayout(layout);
  }

  // ── Per-collection actions ─────────────────────────────────────────────

  Future<void> _openCollectionActions(HomeCollection c) async {
    final unresolved = HomeCollectionsStore.unresolvedAddonIds([c], _addons);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => Theme(
        data: settingsPageTheme(context),
        child: AlertDialog(
          title: Text(c.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_describe(c)),
              if (unresolved.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Needs addons that aren\'t installed:\n'
                  '${unresolved.join('\n')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppThemeScope.of(context).settings.dim,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Folders: ${c.folders.map((f) => f.title).join(', ')}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppThemeScope.of(context).settings.dim,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('delete'),
              child: const Text('Delete'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('toggle'),
              child: Text(c.enabled ? 'Hide from Home' : 'Show on Home'),
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
        await _store.setEnabled(c.id, !c.enabled);
        MainPageBridge.notifyHomeSettingsChanged();
        await _load();
      case 'delete':
        final confirmed = await _confirm(
          title: 'Delete "${c.title}"?',
          body:
              'Its ${c.folders.length} folder(s) leave the Home screen. '
              'Re-import the file to get it back.',
          action: 'Delete',
        );
        if (confirmed && mounted) {
          await _store.remove(c.id);
          MainPageBridge.notifyHomeSettingsChanged();
          await _load();
        }
    }
  }

  Future<void> _removeAll() async {
    if (_collections.isEmpty) return;
    final confirmed = await _confirm(
      title: 'Remove all collections?',
      body: 'Every imported collection is deleted from this profile.',
      action: 'Remove all',
    );
    if (!confirmed || !mounted) return;
    await _store.clear();
    MainPageBridge.notifyHomeSettingsChanged();
    await _load();
  }

  // ── Dialog helpers ─────────────────────────────────────────────────────

  String _describe(HomeCollection c) {
    final folders = c.folders.length;
    final sources = c.sourceCount;
    final parts = [
      '$folders folder${folders == 1 ? '' : 's'}',
      '$sources catalog${sources == 1 ? '' : 's'}',
      if (c.pinToTop) 'pinned to top',
      if (!c.enabled) 'hidden',
    ];
    return parts.join(' · ');
  }

  String _subtitle(HomeCollection c) {
    final unresolved = HomeCollectionsStore.unresolvedAddonIds([c], _addons);
    final base = _describe(c);
    if (unresolved.isEmpty) return base;
    return '$base · ${unresolved.length} addon'
        '${unresolved.length == 1 ? '' : 's'} missing';
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

  Future<void> _showImportResult(HomeCollectionImportResult r) {
    final lines = <String>[
      if (r.added.isNotEmpty)
        'Added: ${r.added.map((c) => c.title).join(', ')}',
      if (r.replaced.isNotEmpty)
        'Updated: ${r.replaced.map((c) => c.title).join(', ')}',
      '${r.folderCount} folder${r.folderCount == 1 ? '' : 's'} in total.',
      if (r.unresolvedAddonIds.isNotEmpty)
        '\nSome folders need addons that aren\'t installed yet:\n'
            '${r.unresolvedAddonIds.join('\n')}\n\n'
            'They show on Home but browse empty until the addon (or one '
            'serving the same catalogs) is installed.',
    ];
    return showDialog<void>(
      context: context,
      builder: (context) => Theme(
        data: settingsPageTheme(context),
        child: AlertDialog(
          title: Text(
            'Imported ${r.collectionCount} collection'
            '${r.collectionCount == 1 ? '' : 's'}',
          ),
          content: SingleChildScrollView(child: Text(lines.join('\n'))),
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
        title: 'Collections',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsPageScaffold(
      title: 'Collections',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.collections_bookmark_rounded,
                  title: 'Collections',
                  subtitle:
                      'Import Nuvio-style collection files — groups of '
                      'folders that bundle addon catalogs into Home rows',
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: 'Import',
                  blurb:
                      'A collection file lists folders (Netflix, Action, …) '
                      'and the addon catalogs behind each. Folders browse '
                      'through the catalog addons you have installed.',
                  children: [
                    SettingsTile(
                      icon: Icons.upload_file_rounded,
                      title: 'Import from file',
                      subtitle: _busy
                          ? 'Importing…'
                          : 'Pick a collections .json on this device',
                      enabled: !_busy,
                      onTap: _importFromFile,
                      focusNode: _firstTileFocusNode,
                    ),
                    SettingsTile(
                      icon: Icons.link_rounded,
                      title: 'Import from link',
                      subtitle: 'Download a collections .json from a URL',
                      enabled: !_busy,
                      onTap: _importFromUrl,
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
                  title: 'Folder layout',
                  blurb:
                      'How a folder shows its lists when you open it. Rows '
                      'stack every list; Tabs show one list at a time '
                      'behind a selector, like Nuvio.',
                  children: [
                    SettingsToggleTile(
                      icon: Icons.tab_rounded,
                      title: 'Tabbed folders',
                      subtitle: _layout == CollectionFolderLayout.tabs
                          ? 'One list at a time, pick it from the List chip'
                          : 'Lists stacked as rows (each with See all)',
                      value: _layout == CollectionFolderLayout.tabs,
                      onChanged: _setTabbed,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsSection(
                  title: 'Your collections',
                  blurb: _collections.isEmpty
                      ? 'Nothing imported yet. Each collection becomes a '
                            'row of folder tiles on Home; hide or arrange '
                            'rows under Home Screen › Home Rows.'
                      : null,
                  children: [
                    for (final c in _collections)
                      SettingsTile(
                        icon: c.enabled
                            ? Icons.folder_rounded
                            : Icons.folder_off_rounded,
                        title: c.title,
                        subtitle: _subtitle(c),
                        tag: c.pinToTop ? 'PINNED' : null,
                        onTap: () => _openCollectionActions(c),
                      ),
                    if (_collections.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No collections yet.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                ),
                if (_collections.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SettingsSection(
                    title: 'Danger Zone',
                    children: [
                      SettingsTile(
                        icon: Icons.delete_sweep_rounded,
                        title: 'Remove all collections',
                        subtitle: 'Delete every imported collection',
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
