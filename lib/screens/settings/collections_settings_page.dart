import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/home_collection.dart';
import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/collection_gif_settings.dart';
import '../../services/home_collections_store.dart';
import '../../services/main_page_bridge.dart';
import '../../services/stremio_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../widgets/text_prompt_dialog.dart';
import '../collections/collection_editor_screen.dart';
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

  CollectionGifMode _gifMode = CollectionGifMode.focused;
  bool _loading = true;
  bool _busy = false;
  bool _refreshPending = false;
  bool _damagedInventory = false;
  bool _syncDeferred = false;
  int _loadToken = 0;
  String? _loadError;
  List<HomeCollection> _collections = const [];
  List<StremioAddon> _addons = const [];
  CollectionFolderLayout _layout = CollectionFolderLayout.rows;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('collections_settings');
    MainPageBridge.addHomeSettingsListener(_onHomeSettingsChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    MainPageBridge.removeHomeSettingsListener(_onHomeSettingsChanged);
    _firstTileFocusNode.dispose();
    super.dispose();
  }

  void _onHomeSettingsChanged() {
    if (_busy) {
      _refreshPending = true;
    } else {
      unawaited(_load(requestFocus: false));
    }
  }

  Future<void> _load({bool requestFocus = true}) async {
    final token = ++_loadToken;
    final session = HomeCollectionsStore.captureSession();
    try {
      final inventory = await _store.getInventory();
      final collections = inventory.collections;
      final layout = await _store.getFolderLayout();
      final gifMode = await CollectionGifSettings.read();
      List<StremioAddon> addons = const [];
      try {
        addons = await StremioService.instance.getAddons();
      } catch (_) {
        // Addons only feed the "missing addon" hints; the page works without.
      }
      if (!mounted || token != _loadToken) return;
      HomeCollectionsStore.checkSession(session);
      setState(() {
        _collections = collections;
        _gifMode = gifMode;
        _damagedInventory = inventory.hadCorruption;
        _syncDeferred = inventory.syncDeferred;
        _addons = addons;
        _layout = layout;
        _loading = false;
        _loadError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (requestFocus &&
            mounted &&
            token == _loadToken &&
            _firstTileFocusNode.context != null) {
          _firstTileFocusNode.requestFocus();
        }
      });
    } catch (_) {
      if (mounted && token == _loadToken) {
        setState(() {
          _loading = false;
          _loadError = 'Could not read collections. Restore a backup or retry.';
        });
      }
    }
  }

  // ── Import paths ───────────────────────────────────────────────────────

  Future<void> _editCollection([HomeCollection? collection]) async {
    final session = HomeCollectionsStore.captureSession();
    final edited = await Navigator.of(context).push<HomeCollection>(
      MaterialPageRoute(
        builder: (_) =>
            CollectionEditorScreen(collection: collection, addons: _addons),
      ),
    );
    if (!mounted || edited == null) return;
    HomeCollectionsStore.checkSession(session);
    await _store.importCollections([edited], installedAddons: _addons);
    MainPageBridge.notifyHomeSettingsChanged();
    await _load();
  }

  Future<void> _exportCollection(HomeCollection collection) async {
    final session = HomeCollectionsStore.captureSession();
    final text = const JsonEncoder.withIndent(
      '  ',
    ).convert([collection.toJson()]);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => Theme(
        data: settingsPageTheme(context),
        child: AlertDialog(
          title: const Text('Export collection'),
          content: Text(
            'Share "${collection.title}" as a Nuvio-compatible JSON file.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'copy'),
              child: const Text('Copy JSON'),
            ),
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, 'file'),
              child: const Text('Save file'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    HomeCollectionsStore.checkSession(session);
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
    } else {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export collection',
        fileName:
            'collection-${collection.id.replaceAll(RegExp(r"[^a-zA-Z0-9_-]"), "_")}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(text)),
      );
      if (path == null) return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          action == 'copy' ? 'Collection JSON copied.' : 'Collection exported.',
        ),
      ),
    );
  }

  Future<void> _importFromFile() => _guarded(() async {
    final session = HomeCollectionsStore.captureSession();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    HomeCollectionsStore.checkSession(session);
    final file = result.files.first;
    if (file.size > HomeCollectionsStore.maxImportBytes) {
      throw const FormatException('That file is too large to be a collection.');
    }
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
    if (!mounted) return;
    HomeCollectionsStore.checkSession(session);
    await _runImport(
      () => _store.importJson(utf8.decode(bytes), installedAddons: _addons),
    );
  });

  Future<void> _importFromUrl() => _guarded(() async {
    final session = HomeCollectionsStore.captureSession();
    final url = await _prompt(
      title: 'Import from link',
      hint: 'https://…/collections.json',
      helper: 'A direct link to a collections JSON file.',
      keyboardType: TextInputType.url,
      action: 'Import',
    );
    if (url == null || url.trim().isEmpty || !mounted) return;
    HomeCollectionsStore.checkSession(session);
    await _runImport(() => _store.importFromUrl(url, installedAddons: _addons));
  });

  Future<void> _importFromPaste() => _guarded(() async {
    final session = HomeCollectionsStore.captureSession();
    final text = await _prompt(
      title: 'Paste collection JSON',
      hint: '[ { "title": "Streaming", "folders": [ … ] } ]',
      helper: 'Paste the contents of a collections JSON file.',
      multiline: true,
      action: 'Import',
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    HomeCollectionsStore.checkSession(session);
    await _runImport(() => _store.importJson(text, installedAddons: _addons));
  });

  /// Runs an import flow unless one is already in progress, surfacing any
  /// failure as a snackbar ([FormatException]s carry user-readable text).
  Future<void> _guarded(Future<void> Function() flow) async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await flow();
    } on FormatException catch (e) {
      _showError(messenger, e.message);
    } catch (e) {
      _showError(messenger, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_refreshPending) {
          _refreshPending = false;
          await _load(requestFocus: false);
        }
      }
    }
  }

  Future<void> _runImport(
    Future<HomeCollectionImportResult> Function() run,
  ) async {
    final result = await run();
    if (!mounted) return;
    MainPageBridge.notifyHomeSettingsChanged();
    await _load(requestFocus: false);
    if (mounted) await _showImportResult(result);
  }

  Future<void> _setTabbed(bool tabbed) => _guarded(() async {
    final layout = tabbed
        ? CollectionFolderLayout.tabs
        : CollectionFolderLayout.rows;
    await _store.setFolderLayout(layout);
    if (!mounted) return;
    setState(() => _layout = layout);
    MainPageBridge.notifyHomeSettingsChanged();
  });

  // ── Per-collection actions ─────────────────────────────────────────────

  Future<void> _openCollectionActions(HomeCollection c) async {
    final session = HomeCollectionsStore.captureSession();
    final unresolved = _issuesFor(c);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => Theme(
        data: settingsPageTheme(context),
        child: AlertDialog(
          scrollable: true,
          title: Text(c.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_describe(c)),
              if (unresolved.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Sources that need attention:\n'
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
              onPressed: () => Navigator.of(context).pop('edit'),
              child: const Text('Edit'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('export'),
              child: const Text('Export JSON'),
            ),
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
    HomeCollectionsStore.checkSession(session);
    switch (action) {
      case 'edit':
        await _editCollection(c);
      case 'export':
        await _exportCollection(c);
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
          HomeCollectionsStore.checkSession(session);
          await _store.remove(c.id);
          MainPageBridge.notifyHomeSettingsChanged();
          await _load();
        }
    }
  }

  Future<void> _resetDamagedInventory() => _guarded(() async {
    final session = HomeCollectionsStore.captureSession();
    final confirmed = await _confirm(
      title: 'Reset damaged collections?',
      body:
          'This removes the saved collections from this profile. You can then import a collection file or restore a backup.',
      action: 'Reset collections',
    );
    if (!confirmed || !mounted) return;
    HomeCollectionsStore.checkSession(session);
    await _store.clear();
    MainPageBridge.notifyHomeSettingsChanged();
    await _load(requestFocus: false);
  });

  Future<void> _removeAll() async {
    final session = HomeCollectionsStore.captureSession();
    if (_collections.isEmpty) return;
    final confirmed = await _confirm(
      title: 'Remove all collections?',
      body: 'Every imported collection is deleted from this profile.',
      action: 'Remove all',
    );
    if (!confirmed || !mounted) return;
    HomeCollectionsStore.checkSession(session);
    await _store.clear();
    MainPageBridge.notifyHomeSettingsChanged();
    await _load();
  }

  // ── Dialog helpers ─────────────────────────────────────────────────────

  Set<String> _issuesFor(HomeCollection c) => {
    for (final folder in c.folders)
      for (final source in folder.sources)
        if (HomeCollectionsStore.sourceIssue(source, _addons) case final issue?)
          issue,
  };

  String _describe(HomeCollection c) {
    final folders = c.folders.length;
    final sources = c.sourceCount;
    final parts = [
      '$folders folder${folders == 1 ? '' : 's'}',
      '$sources source${sources == 1 ? '' : 's'}',
      if (c.pinToTop) 'pinned to top',
      if (!c.enabled) 'hidden',
    ];
    return parts.join(' · ');
  }

  String _subtitle(HomeCollection c) {
    final unresolved = _issuesFor(c);
    final base = _describe(c);
    if (unresolved.isEmpty) return base;
    return '$base · ${unresolved.length} source(s) need attention';
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
          scrollable: true,
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
      for (final issue in {
        ...r.added.expand(_issuesFor),
        ...r.replaced.expand(_issuesFor),
      })
        '\n$issue',
    ];
    return showDialog<void>(
      context: context,
      builder: (context) => Theme(
        data: settingsPageTheme(context),
        child: AlertDialog(
          scrollable: true,
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
    if (!messenger.mounted) return;
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
    if (_loadError != null) {
      return SettingsPageScaffold(
        title: 'Collections',
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
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
                if (_syncDeferred)
                  const SettingsSection(
                    title: 'Collection sync paused',
                    blurb:
                        'The shared collections exceed this device’s storage capacity. '
                        'Resume and watched state still sync. Remove collections on another device '
                        'to reduce the shared inventory; your current collections are kept here.',
                    children: [],
                  ),
                if (_damagedInventory)
                  SettingsSection(
                    title: 'Damaged collection data',
                    blurb:
                        'Valid collections are still available. Reset the saved data or restore a backup to recover.',
                    children: [
                      SettingsTile(
                        icon: Icons.restore_rounded,
                        title: 'Reset damaged collections',
                        subtitle:
                            'Clear the saved inventory so it can be imported again',
                        enabled: !_busy,
                        onTap: _resetDamagedInventory,
                      ),
                    ],
                  ),
                SettingsSection(
                  title: 'Import',
                  blurb:
                      'Create folders or import a Nuvio collection. Sources '
                      'can use installed addon catalogs, TMDB, or public Trakt lists.',
                  children: [
                    SettingsTile(
                      icon: Icons.create_new_folder_outlined,
                      title: 'Create collection',
                      subtitle: 'Choose folders, artwork, and sources',
                      enabled: !_busy,
                      onTap: () => _guarded(() => _editCollection()),
                    ),
                    SettingsTile(
                      icon: Icons.upload_file_rounded,
                      title: 'Import from file',
                      subtitle: 'Pick a collections .json on this device',
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
                  title: 'Collection GIF playback',
                  blurb: 'Choose how folder GIFs play on this device. Video previews are unchanged.',
                  children: [
                    IgnorePointer(
                      ignoring: _busy,
                      child: ExcludeFocus(
                        excluding: _busy,
                        child: SettingsSelectDropdown(
                          key: ValueKey(_gifMode),
                          value: _gifMode.name,
                          options: const [
                            SettingsSelectOption('visible', 'Animate visible GIFs'),
                            SettingsSelectOption('focused', 'On focus or hover'),
                            SettingsSelectOption('off', 'Off'),
                          ],
                          onChanged: (value) => _guarded(() async {
                            final mode = CollectionGifMode.values.byName(value);
                            await CollectionGifSettings.write(mode);
                            if (!mounted) return;
                            setState(() => _gifMode = mode);
                            MainPageBridge.notifyHomeSettingsChanged();
                          }),
                        ),
                      ),
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
                    IgnorePointer(
                      ignoring: _busy,
                      child: ExcludeFocus(
                        excluding: _busy,
                        child: Opacity(
                          opacity: _busy ? 0.5 : 1,
                          child: SettingsToggleTile(
                            icon: Icons.tab_rounded,
                            title: 'Tabbed folders',
                            subtitle: _layout == CollectionFolderLayout.tabs
                                ? 'One list at a time, pick it from the List chip'
                                : 'Lists stacked as rows (each with See all)',
                            value: _layout == CollectionFolderLayout.tabs,
                            onChanged: _setTabbed,
                          ),
                        ),
                      ),
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
                        onTap: () => _guarded(() => _openCollectionActions(c)),
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
                        onTap: () => _guarded(_removeAll),
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
