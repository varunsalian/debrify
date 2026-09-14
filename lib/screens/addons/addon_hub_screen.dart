import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:yaml/yaml.dart';

import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/android_native_downloader.dart';
import '../../services/engine/config_loader.dart';
import '../../services/engine/engine_registry.dart';
import '../../services/engine/local_engine_storage.dart';
import '../../services/engine/remote_engine_manager.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/stremio_marketplace_service.dart';
import '../../services/stremio_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/see_all/see_all_theme.dart';
import '../../widgets/see_all/stremio_dropdown.dart';
import '../../widgets/tv_text_field.dart';

/// What the hub is managing: Stremio addons or torrent-engine plugins. They are
/// different features, so they get their own top-level dropdown instead of being
/// mixed into one source list.
enum _HubKind { addons, engines }

/// Which addon list is shown when [_HubKind.addons] is active. Official/Community
/// are 1-click marketplaces (Stremio's official collection + the community
/// `addon_catalog`).
enum _AddonSource { installed, official, community }

/// A single, Stremio-themed home for addons: one list with a source + type
/// filter, a search box, an "Add addon" URL flow, and a 1-click Discover
/// marketplace — styled with the same purple Discover kit (see_all_theme +
/// StremioDropdown) as the catalog browser.
class AddonHubScreen extends StatefulWidget {
  const AddonHubScreen({super.key});

  @override
  State<AddonHubScreen> createState() => _AddonHubScreenState();
}

class _AddonHubScreenState extends State<AddonHubScreen> {
  static const int _tabIndex = 7; // Addons slot in the main nav.

  final StremioService _stremio = StremioService.instance;
  final _marketplace = StremioMarketplaceService.instance;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _kindFocus = FocusNode(debugLabel: 'hub-kind');
  final FocusNode _sourceFocus = FocusNode(debugLabel: 'hub-source');
  final FocusNode _typeFocus = FocusNode(debugLabel: 'hub-type');
  final FocusNode _addFocus = FocusNode(debugLabel: 'hub-add');
  final FocusNode _moreFocus = FocusNode(debugLabel: 'hub-more');
  final FocusNode _searchFocus = FocusNode(debugLabel: 'hub-search');
  final FocusNode _searchBtnFocus = FocusNode(debugLabel: 'hub-search-btn');
  final FocusNode _metadataFocus = FocusNode(
    debugLabel: 'hub-metadata-provider',
  );

  /// Attached to the first focusable of the installed/engine lists (single-focus
  /// cards), so DOWN from the filter bar deterministically lands on item 1.
  final FocusNode _firstRowFocus = FocusNode(debugLabel: 'hub-first-row');

  /// One focus node per focusable marketplace row (its primary button). Market
  /// rows have variable buttons (Install / Install+Configure / Configure), so
  /// geometric DOWN is unreliable — vertical moves go through these instead, and
  /// always land on the NEXT row's first button regardless of its layout.
  final _RowNav _marketNav = _RowNav();

  VoidCallback? _tvFocusHandler;

  bool _isTv = false;

  _HubKind _kind = _HubKind.addons;
  _AddonSource _source = _AddonSource.installed;
  String _typeFilter = ''; // '' == All
  String _search = '';
  bool _searchOpen = false;

  // Installed addons.
  List<StremioAddon> _installed = const [];
  bool _installedLoading = true;
  String? _metadataProviderPreference;

  // Marketplace addons (Official / Community).
  List<MarketplaceAddon> _market = const [];
  bool _marketLoading = false;
  String? _marketError;
  _AddonSource? _marketLoadedFor; // which source _market currently holds

  /// Whether any debrid/cloud provider is configured — drives the "Needs debrid"
  /// honesty badge on stream addons (debrify can't play torrents P2P).
  bool _hasDebrid = true;

  // Torrent engines (the "Torrent Engines" kind).
  final RemoteEngineManager _remoteEngines = RemoteEngineManager();
  final LocalEngineStorage _localEngines = LocalEngineStorage.instance;
  List<ImportedEngineMetadata> _importedEngines = const [];
  List<RemoteEngineInfo> _availableEngines = const [];
  List<RemoteEngineInfo> _knownRemoteEngines = const [];
  bool _enginesLoading = false;
  String? _enginesError;
  bool _enginesLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('addon_hub');
    _stremio.addAddonsChangedListener(_onAddonsChanged);
    LocalEngineStorage.changes.addListener(_onEnginesChanged);
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q != _search) setState(() => _search = q);
    });

    _tvFocusHandler = () => _kindFocus.requestFocus();
    MainPageBridge.registerTvContentFocusHandler(_tabIndex, _tvFocusHandler!);

    AndroidNativeDownloader.isTelevision().then((tv) {
      if (mounted) setState(() => _isTv = tv);
    });

    _loadDebridState();
    _loadInstalled();
  }

  Future<void> _loadDebridState() async {
    final configured = await Future.wait([
      StorageService.hasRealDebridCredential(),
      StorageService.hasTorboxCredential(),
      StorageService.hasPremiumizeCredential(),
      StorageService.hasAllDebridCredential(),
    ]);
    final has = configured.any((value) => value);
    if (mounted) setState(() => _hasDebrid = has);
  }

  @override
  void dispose() {
    _stremio.removeAddonsChangedListener(_onAddonsChanged);
    LocalEngineStorage.changes.removeListener(_onEnginesChanged);
    if (_tvFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(
        _tabIndex,
        _tvFocusHandler!,
      );
    }
    _searchController.dispose();
    _kindFocus.dispose();
    _sourceFocus.dispose();
    _typeFocus.dispose();
    _addFocus.dispose();
    _moreFocus.dispose();
    _searchFocus.dispose();
    _searchBtnFocus.dispose();
    _metadataFocus.dispose();
    _firstRowFocus.dispose();
    _marketNav.dispose();
    _remoteEngines.dispose();
    super.dispose();
  }

  void _onAddonsChanged() => _loadInstalled();

  int _installedLoadRevision = 0;

  Future<void> _loadInstalled() async {
    final revision = ++_installedLoadRevision;
    if (mounted) setState(() => _installedLoading = true);
    try {
      // This is the management inventory. It must include disabled addons so
      // they remain visible and can be enabled again; the normal read path
      // intentionally excludes profile-locally disabled rows for playback.
      final results = await Future.wait<Object?>([
        _stremio.getAddonsForManagement(),
        _stremio.getMetadataProviderPreference(),
      ]);
      final addons = results[0] as List<StremioAddon>;
      final metadataPreference = results[1] as String?;
      if (mounted && revision == _installedLoadRevision) {
        setState(() {
          _installed = addons;
          _metadataProviderPreference = metadataPreference;
          _installedLoading = false;
        });
      }
    } catch (_) {
      if (mounted && revision == _installedLoadRevision) {
        setState(() => _installedLoading = false);
      }
    }
  }

  Future<void> _loadMarket(_AddonSource source, {bool force = false}) async {
    if (!mounted) return;
    setState(() {
      _marketLoading = true;
      _marketError = null;
      _marketLoadedFor = source;
    });
    try {
      final addons = source == _AddonSource.community
          ? await _marketplace.fetchCommunity(forceRefresh: force)
          : await _marketplace.fetchOfficial(forceRefresh: force);
      if (mounted && _marketLoadedFor == source) {
        setState(() {
          _market = addons;
          _marketLoading = false;
        });
      }
    } catch (e) {
      if (mounted && _marketLoadedFor == source) {
        setState(() {
          _marketError = e.toString().replaceFirst('Exception: ', '');
          _marketLoading = false;
        });
      }
    }
  }

  // ── Torrent engines ────────────────────────────────────────────────────────

  int _engineLoadRevision = 0;
  Future<void> _onEnginesChanged() async {
    final revision = ++_engineLoadRevision;
    try {
      final imported = await _localEngines.getImportedEngines();
      if (!mounted || revision != _engineLoadRevision) return;
      setState(() {
        _importedEngines = imported;
        final installed = imported.map((e) => e.id).toSet();
        _availableEngines = _knownRemoteEngines
            .where((e) => !installed.contains(e.id))
            .toList();
        _enginesLoading = false;
        _enginesError = null;
      });
    } catch (_) {
      if (mounted && revision == _engineLoadRevision) {
        setState(() {
          _enginesLoading = false;
          _enginesError = 'Could not refresh installed engines';
        });
      }
    }
  }

  Future<void> _loadEngines() async {
    final revision = ++_engineLoadRevision;
    setState(() {
      _enginesLoading = true;
      _enginesError = null;
      _enginesLoadedOnce = true;
    });
    try {
      final imported = await _localEngines.getImportedEngines();
      final remote = await _remoteEngines.fetchAvailableEngines();
      if (!mounted) return;
      _knownRemoteEngines = remote;
      if (revision != _engineLoadRevision) {
        await _onEnginesChanged();
        return;
      }
      final importedIds = imported.map((e) => e.id).toSet();
      if (mounted && revision == _engineLoadRevision) {
        setState(() {
          _importedEngines = imported;
          _availableEngines = remote
              .where((e) => !importedIds.contains(e.id))
              .toList();
          _enginesLoading = false;
        });
      }
    } catch (e) {
      if (mounted && revision == _engineLoadRevision) {
        setState(() {
          _enginesError = e.toString().replaceFirst('Exception: ', '');
          _enginesLoading = false;
        });
      }
    }
  }

  Future<void> _installEngine(RemoteEngineInfo engine) async {
    final messenger = ScaffoldMessenger.of(context);
    _showBlockingProgress('Installing ${engine.displayName}…');
    try {
      final yaml = await _remoteEngines.downloadEngineYaml(engine.fileName);
      if (yaml == null) throw Exception('Failed to download engine config');
      await _localEngines.saveEngine(
        engineId: engine.id,
        fileName: engine.fileName,
        yamlContent: yaml,
        displayName: engine.displayName,
        icon: engine.icon,
      );
      ConfigLoader().clearCache();
      await EngineRegistry.instance.reload();
      _dismissBlockingProgress();
      await _loadEngines();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${engine.displayName} installed')),
      );
    } catch (e) {
      _dismissBlockingProgress();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to install: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteEngine(ImportedEngineMetadata engine) async {
    final app = AppThemeScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _HubDialog(
        title: 'Delete engine',
        content: Text(
          'Delete "${engine.displayName}"?',
          style: TextStyle(color: app.fade(app.core.tx, 0.75)),
        ),
        actions: [
          _HubDialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(ctx).pop(false),
          ),
          _HubDialogButton(
            label: 'Delete',
            danger: true,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _localEngines.deleteEngine(engine.id);
      ConfigLoader().clearCache();
      await EngineRegistry.instance.reload();
      await _loadEngines();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${engine.displayName} deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _importEngineFromFile() async {
    final messenger = ScaffoldMessenger.of(context);
    // Captured with the messenger, before any await: the replace-confirmation
    // dialog below opens after the file picker returns.
    final app = AppThemeScope.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final lower = file.name.toLowerCase();
      if (!lower.endsWith('.yaml') && !lower.endsWith('.yml')) {
        throw Exception('Please select a YAML file (.yaml or .yml)');
      }
      final String yamlContent;
      if (file.bytes != null) {
        yamlContent = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        yamlContent = String.fromCharCodes(await file.xFile.readAsBytes());
      } else {
        throw Exception('Could not read file content');
      }
      final yaml = loadYaml(yamlContent);
      final engineId = yaml is Map ? yaml['id'] as String? : null;
      final displayName = yaml is Map ? yaml['display_name'] as String? : null;
      final icon = yaml is Map ? yaml['icon'] as String? : null;
      if (engineId == null || engineId.isEmpty) {
        throw Exception('YAML must contain an "id" field');
      }
      if (displayName == null || displayName.isEmpty) {
        throw Exception('YAML must contain a "display_name" field');
      }
      final existing = await _localEngines.getImportedEngines();
      if (existing.any((e) => e.id == engineId)) {
        if (!mounted) return;
        final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => _HubDialog(
            title: 'Engine already exists',
            content: Text(
              'Replace the existing "$engineId"?',
              style: TextStyle(color: app.fade(app.core.tx, 0.75)),
            ),
            actions: [
              _HubDialogButton(
                label: 'Cancel',
                onTap: () => Navigator.of(ctx).pop(false),
              ),
              _HubDialogButton(
                label: 'Replace',
                primary: true,
                onTap: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        );
        if (replace != true) return;
      }
      if (!mounted) return;
      _showBlockingProgress('Importing $displayName…');
      await _localEngines.saveEngine(
        engineId: engineId,
        fileName: file.name,
        yamlContent: yamlContent,
        displayName: displayName,
        icon: icon,
      );
      ConfigLoader().clearCache();
      await EngineRegistry.instance.reload();
      _dismissBlockingProgress();
      await _loadEngines();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('$displayName imported')));
    } catch (e) {
      _dismissBlockingProgress();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool _blockingProgressUp = false;
  void _showBlockingProgress(String message) {
    final app = AppThemeScope.of(context);
    _blockingProgressUp = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: app.seeAll.panel,
        shape: RoundedRectangleBorder(
          borderRadius: app.shape.br(16),
          side: BorderSide(color: app.seeAll.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: app.seeAll.accent,
                ),
              ),
              const SizedBox(width: 16),
              Flexible(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  void _dismissBlockingProgress() {
    if (_blockingProgressUp && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      _blockingProgressUp = false;
    }
  }

  /// Move focus from the filter bar down to the first row of whatever list is
  /// showing (market rows use their own nav pool; installed/engines use the
  /// single first-card node).
  void _focusFirstRow() {
    final isMarket =
        _kind == _HubKind.addons &&
        (_source == _AddonSource.official || _source == _AddonSource.community);
    if (isMarket) {
      _marketNav.focus(0);
    } else if (_kind == _HubKind.addons &&
        _source == _AddonSource.installed &&
        _metadataFocus.context != null) {
      _metadataFocus.requestFocus();
    } else if (_firstRowFocus.context != null) {
      _firstRowFocus.requestFocus();
    }
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    } else {
      _searchController.clear();
      // Hand focus back to the search button so the remote isn't stranded on a
      // widget that just left the tree.
      _searchBtnFocus.requestFocus();
    }
  }

  void _selectKind(_HubKind kind) {
    if (kind == _kind) return;
    setState(() => _kind = kind);
    if (kind == _HubKind.engines && !_enginesLoadedOnce) _loadEngines();
  }

  void _selectSource(_AddonSource source) {
    if (source == _source) return;
    setState(() => _source = source);
    if (source != _AddonSource.installed && _marketLoadedFor != source) {
      _loadMarket(source);
    }
  }

  bool _isInstalled(MarketplaceAddon m) {
    // Match by manifest id OR transport URL. Note: a configurable addon installed
    // via the Configure→paste flow has a different (configured) URL than its
    // marketplace [config] transportUrl, so it's recognised only by id — fine for
    // addons that keep their id after configuration (the common case).
    for (final a in _installed) {
      if (a.id == m.id || a.manifestUrl == m.transportUrl) return true;
    }
    return false;
  }

  bool _matchesFilters({required List<String> types, required String name}) {
    if (_typeFilter.isNotEmpty && !types.contains(_typeFilter)) return false;
    if (_search.isNotEmpty &&
        !name.toLowerCase().contains(_search.toLowerCase())) {
      return false;
    }
    return true;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _installFromMarket(MarketplaceAddon m, int? fromNav) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final addon = await _stremio.addAddon(m.transportUrl);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${addon.name} installed')),
      );
      // The row we just installed becomes a non-focusable "Installed" label, so
      // its button — which held DPAD focus — vanishes. Reload now (the change
      // listener also fires) and, once the list rebuilds, land focus on whatever
      // row now occupies this slot (or the previous one / the filter bar) so the
      // TV remote is never stranded.
      await _loadInstalled();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || fromNav == null) return;
        if (!_marketNav.focus(fromNav) && !_marketNav.focus(fromNav - 1)) {
          _searchBtnFocus.requestFocus();
        }
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _configureInBrowser(MarketplaceAddon m) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(m.configureUrl);
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!mounted) return;
    if (!opened) {
      // TV / no browser: copy the URL so the user can configure elsewhere.
      await Clipboard.setData(ClipboardData(text: m.configureUrl));
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Configure link copied — open it in a browser, then '
            'paste the configured URL into "Add addon".',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _addByUrl() async {
    final app = AppThemeScope.of(context);
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => _HubDialog(
        title: 'Add addon',
        content: TvTextField(
          controller: controller,
          autofocus: true,
          cursorColor: app.seeAll.accent,
          decoration: InputDecoration(
            hintText: 'https://…/manifest.json',
            hintStyle: TextStyle(color: app.fade(app.core.tx, 0.35)),
            enabledBorder: OutlineInputBorder(
              borderRadius: app.shape.br(11),
              borderSide: BorderSide(color: app.seeAll.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: app.shape.br(11),
              borderSide: BorderSide(color: app.seeAll.accent, width: 2),
            ),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          _HubDialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(ctx).pop(),
          ),
          _HubDialogButton(
            label: 'Add',
            primary: true,
            onTap: () => Navigator.of(ctx).pop(controller.text.trim()),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final addon = await _stremio.addAddon(url);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('${addon.name} added')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _importJson() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (!file.name.toLowerCase().endsWith('.json')) {
        throw Exception('Please select the Stremio addon JSON export.');
      }
      final List<int> bytes;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        bytes = await file.xFile.readAsBytes();
      } else {
        throw Exception('Could not read the selected file.');
      }
      final importResult = await _stremio.importAddonsFromJson(
        utf8.decode(bytes),
      );
      if (!mounted) return;
      await _showImportResult(importResult);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showImportResult(StremioAddonImportResult r) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => _HubDialog(
        title: 'Import complete',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _importRow('Found', '${r.discovered}'),
            _importRow('Imported', '${r.imported}'),
            _importRow('Already installed', '${r.skippedDuplicates}'),
            if (r.skippedUnsupported > 0)
              _importRow('Unsupported', '${r.skippedUnsupported}'),
            if (r.failed > 0) _importRow('Failed', '${r.failed}'),
          ],
        ),
        actions: [
          _HubDialogButton(
            label: 'Done',
            primary: true,
            onTap: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  Widget _importRow(String label, String value) {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: app.fade(app.core.tx, 0.7))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Future<void> _updateAll() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await _stremio.refreshAllAddons();
      if (!mounted) return;
      final parts = <String>[];
      if (result.updated > 0) parts.add('${result.updated} updated');
      if (result.unchanged > 0) parts.add('${result.unchanged} up to date');
      if (result.failed > 0) parts.add('${result.failed} failed');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            parts.isEmpty ? 'No addons to update' : parts.join('  ·  '),
          ),
          backgroundColor: result.failed > 0 ? Colors.orange.shade800 : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteAll() async {
    final count = _installed.length;
    if (count == 0) return;
    final app = AppThemeScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final int sharedCount;
    try {
      sharedCount = await _stremio.sharedAddonCount();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to check sharing: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!mounted) return;
    final hasSharedAddons = sharedCount > 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _HubDialog(
        title: 'Delete all addons?',
        content: Text(
          hasSharedAddons
              ? '$sharedCount addon${sharedCount == 1 ? ' is' : 's are'} '
                    'shared with other profiles. Deleting all addons will '
                    'also remove those addons from every shared profile.'
              : 'This removes all $count installed Stremio '
                    'addon${count == 1 ? '' : 's'} from Debrify.',
          style: TextStyle(color: app.fade(app.core.tx, 0.75)),
        ),
        actions: [
          _HubDialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(ctx).pop(false),
          ),
          _HubDialogButton(
            label: 'Delete all',
            danger: true,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _stremio.clearAllAddons(revokeSharedProfiles: hasSharedAddons);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Deleted $count addon${count == 1 ? '' : 's'}')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // storageKey, NOT manifestUrl: under profiles an addon is a connection
  // resource and its key is that resource's id, so the URL matches nothing
  // and the toggle silently did nothing at all.
  Future<void> _toggleAddon(StremioAddon a) =>
      _stremio.setAddonEnabled(a.storageKey, !a.enabled);

  Future<void> _updateAddon(StremioAddon a) async {
    final messenger = ScaffoldMessenger.of(context);
    final refreshed = await _stremio.refreshAddon(a.manifestUrl);
    if (!mounted) return;
    if (refreshed == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to update ${a.name}'),
          backgroundColor: Colors.red,
        ),
      );
    } else if (refreshed.version != a.version) {
      final detail = (a.version != null && refreshed.version != null)
          ? ' (v${a.version} → v${refreshed.version})'
          : '';
      messenger.showSnackBar(
        SnackBar(content: Text('${a.name} updated$detail')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('${a.name} is already up to date')),
      );
    }
  }

  Future<void> _removeAddon(StremioAddon a) async {
    final app = AppThemeScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final int borrowerCount;
    try {
      borrowerCount = await _stremio.addonBorrowerCount(a.manifestUrl);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to check sharing: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!mounted) return;
    final isShared = borrowerCount > 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _HubDialog(
        title: 'Remove addon',
        content: Text(
          isShared
              ? '"${a.name}" is shared with $borrowerCount other '
                    'profile${borrowerCount == 1 ? '' : 's'}. Removing it '
                    'will also remove it from those shared profiles.'
              : 'Remove "${a.name}" from your addons?',
          style: TextStyle(color: app.fade(app.core.tx, 0.75)),
        ),
        actions: [
          _HubDialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(ctx).pop(false),
          ),
          _HubDialogButton(
            label: 'Remove',
            danger: true,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _stremio.removeAddon(a.manifestUrl, revokeSharedProfiles: isShared);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('${a.name} removed')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to remove: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Sheets / menus ───────────────────────────────────────────────────────

  void _showOptions(StremioAddon a) {
    final app = AppThemeScope.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.seeAll.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _AddonOptionsSheet(
        addon: a,
        onToggle: () {
          Navigator.of(ctx).pop();
          _toggleAddon(a);
        },
        onUpdate: () {
          Navigator.of(ctx).pop();
          _updateAddon(a);
        },
        onDetails: () {
          Navigator.of(ctx).pop();
          _showDetails(a);
        },
        onRemove: () {
          Navigator.of(ctx).pop();
          _removeAddon(a);
        },
      ),
    );
  }

  void _showDetails(StremioAddon a) {
    final app = AppThemeScope.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => _HubDialog(
        title: a.name,
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (a.description != null) ...[
                Text(
                  a.description!,
                  style: TextStyle(color: app.fade(app.core.tx, 0.8)),
                ),
                const SizedBox(height: 14),
              ],
              _detailRow('ID', a.id),
              if (a.version != null) _detailRow('Version', a.version!),
              _detailRow(
                'Types',
                a.types.isEmpty ? 'None' : a.types.join(', '),
              ),
              _detailRow(
                'Resources',
                a.resources.isEmpty ? 'None' : a.resources.join(', '),
              ),
              const SizedBox(height: 10),
              SelectableText(
                a.manifestUrl,
                style: TextStyle(
                  color: app.seeAll.accent2,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        actions: [
          _HubDialogButton(
            label: 'Copy URL',
            onTap: () {
              Clipboard.setData(ClipboardData(text: a.manifestUrl));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL copied to clipboard')),
              );
            },
          ),
          _HubDialogButton(
            label: 'Close',
            primary: true,
            onTap: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: app.fade(app.core.tx, 0.4),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }

  Future<void> _showActionsMenu() async {
    final app = AppThemeScope.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final btn = _moreFocus.context?.findRenderObject() as RenderBox?;
    if (overlay == null || btn == null) return;
    final topLeft = btn.localToGlobal(
      Offset(0, btn.size.height + 6),
      ancestor: overlay,
    );
    final pos = RelativeRect.fromRect(
      Rect.fromPoints(
        topLeft,
        btn.localToGlobal(btn.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final choice = await showMenu<String>(
      context: context,
      position: pos,
      color: app.seeAll.panel2,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: app.shape.br(14),
        side: BorderSide(color: app.seeAll.line),
      ),
      items: [
        _menuItem('import', Icons.file_upload_outlined, 'Import from JSON'),
        _menuItem('update', Icons.sync_rounded, 'Update all'),
        _menuItem(
          'delete',
          Icons.delete_outline_rounded,
          'Delete all',
          danger: true,
        ),
      ],
    );
    switch (choice) {
      case 'import':
        _importJson();
        break;
      case 'update':
        _updateAll();
        break;
      case 'delete':
        _deleteAll();
        break;
    }
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final app = AppThemeScope.of(context);
    final color = danger ? const Color(0xFFEF4444) : app.core.tx;
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  /// Page-level DPAD policy. On TV the sidebar shares the screen's focus scope,
  /// so default geometric traversal can "escape" sideways/down into it (focusing
  /// a rail icon pops the sidebar open). The [FocusScope] in [build] contains all
  /// directional moves to this page; this handler then implements the ONE
  /// deliberate exit: a LEFT press that can't move anywhere inside the hub goes
  /// to the sidebar.
  KeyEventResult _onPageKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    // Let the search field keep left/right for caret movement.
    if (_searchFocus.hasFocus) return KeyEventResult.ignored;
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    // Move within the hub ONLY when there's a focusable genuinely to the left
    // in the same horizontal band (e.g. Configure → Install). We can't lean on
    // focusInDirection's return value here: it's greedy and, from a card's
    // leftmost button (Install), jumps diagonally up to the filter bar and
    // reports moved=true — which would swallow the deliberate LEFT exit to the
    // sidebar. So gate on a real in-band left neighbour instead.
    if (_hasLeftNeighbour(primary)) {
      primary.focusInDirection(TraversalDirection.left);
      return KeyEventResult.handled;
    }
    if (MainPageBridge.focusTvSidebar != null) {
      MainPageBridge.focusTvSidebar!();
    }
    return KeyEventResult.handled;
  }

  /// True if any focusable in this scope sits to the LEFT of [primary] while
  /// vertically overlapping its row band — i.e. a real left move exists and
  /// LEFT should stay inside the hub rather than exit to the sidebar.
  bool _hasLeftNeighbour(FocusNode primary) {
    final rect = primary.rect;
    final scope = primary.enclosingScope;
    if (scope == null) return false;
    for (final n in scope.traversalDescendants) {
      if (n == primary) continue;
      final r = n.rect;
      final overlapsVertically = r.top < rect.bottom && r.bottom > rect.top;
      if (overlapsVertically && r.center.dx < rect.center.dx - 1) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Scaffold(
      backgroundColor: app.seeAll.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.75),
            radius: 1.35,
            colors: [
              Color(0xFF241E44),
              Color(0xFF161327),
              Color(0xFF0F0D1D),
              kSeeAllBg,
            ],
            stops: [0.0, 0.38, 0.68, 1.0],
          ),
        ),
        child: SafeArea(
          // Own scope: directional focus search never leaves the hub (the TV
          // sidebar is reached only via _onPageKey's explicit LEFT exit, and it
          // can still focus back INTO the hub via requestFocus).
          child: FocusScope(
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onPageKey,
              child: FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    _buildFilterBar(),
                    Expanded(child: _buildBody()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 14, 24, 8),
      child: Text(
        'Addons',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    final isAddon = _kind == _HubKind.addons;
    return LayoutBuilder(
      builder: (context, c) {
        // Phone-width: the labelled dropdowns + buttons wrap into four ragged
        // rows that eat half the screen. Compose a compact three-row bar
        // instead (labels dropped — the values are self-explanatory) and keep
        // the free-flowing Wrap for wide layouts.
        final narrow = c.maxWidth < 480;

        final manageDd = StremioDropdown<_HubKind>(
          // Stremio addons and torrent engines are separate features — the
          // first dropdown picks which one is being managed.
          label: narrow ? null : 'Manage',
          value: _kind,
          focusNode: _kindFocus,
          isTelevision: _isTv,
          options: const [
            StremioDropdownOption(_HubKind.addons, 'Stremio Addons'),
            StremioDropdownOption(_HubKind.engines, 'Torrent Engines'),
          ],
          onSelected: _selectKind,
        );
        final sourceDd = StremioDropdown<_AddonSource>(
          label: narrow ? null : 'Source',
          value: _source,
          focusNode: _sourceFocus,
          isTelevision: _isTv,
          options: const [
            StremioDropdownOption(_AddonSource.installed, 'Installed'),
            StremioDropdownOption(_AddonSource.official, 'Official'),
            StremioDropdownOption(_AddonSource.community, 'Community'),
          ],
          onSelected: _selectSource,
        );
        final typeDd = StremioDropdown<String>(
          label: narrow ? null : 'Type',
          value: _typeFilter,
          focusNode: _typeFocus,
          isTelevision: _isTv,
          options: const [
            StremioDropdownOption('', 'All'),
            StremioDropdownOption('movie', 'Movies'),
            StremioDropdownOption('series', 'Series'),
            StremioDropdownOption('channel', 'Channels'),
            StremioDropdownOption('tv', 'TV'),
            StremioDropdownOption('anime', 'Anime'),
          ],
          onSelected: (v) => setState(() => _typeFilter = v),
        );
        final searchBtn = _HubActionButton(
          focusNode: _searchBtnFocus,
          icon: Icons.search_rounded,
          onTap: _toggleSearch,
        );
        final addBtn = _HubActionButton(
          focusNode: _addFocus,
          icon: Icons.add_rounded,
          label: 'Add addon',
          primary: true,
          expand: narrow,
          onTap: _addByUrl,
        );
        final moreBtn = _HubActionButton(
          focusNode: _moreFocus,
          icon: Icons.more_horiz_rounded,
          onTap: _showActionsMenu,
        );
        final importBtn = _HubActionButton(
          icon: Icons.file_upload_outlined,
          label: 'Import YAML',
          primary: true,
          expand: narrow,
          onTap: _importEngineFromFile,
        );
        final refreshBtn = _HubActionButton(
          icon: Icons.refresh_rounded,
          onTap: _loadEngines,
        );

        final Widget controls;
        if (narrow) {
          controls = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Row 1: what's being managed + overflow / refresh.
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: manageDd,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (isAddon) moreBtn else refreshBtn,
                ],
              ),
              const SizedBox(height: 10),
              if (isAddon) ...[
                // Row 2: the filters + search toggle.
                Row(
                  children: [
                    sourceDd,
                    const SizedBox(width: 10),
                    typeDd,
                    const Spacer(),
                    searchBtn,
                  ],
                ),
                const SizedBox(height: 10),
                // Row 3: the primary action gets the full width.
                addBtn,
              ] else
                importBtn,
            ],
          );
        } else {
          controls = Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              manageDd,
              if (isAddon) ...[
                sourceDd,
                typeDd,
                searchBtn,
                addBtn,
                moreBtn,
              ] else ...[
                importBtn,
                refreshBtn,
              ],
            ],
          );
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
            narrow ? 16 : 24,
            6,
            narrow ? 16 : 24,
            12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // DOWN from any filter-bar control goes deterministically to the
              // search field (when open) or the first list row — geometric
              // traversal's direction-history would otherwise return to whatever
              // row the user last came from.
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                    return KeyEventResult.ignored;
                  }
                  if (event.logicalKey != LogicalKeyboardKey.arrowDown) {
                    return KeyEventResult.ignored;
                  }
                  if (_searchOpen || _search.isNotEmpty) {
                    _searchFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                  _focusFirstRow();
                  return KeyEventResult.handled;
                },
                child: controls,
              ),
              if (isAddon && (_searchOpen || _search.isNotEmpty)) ...[
                const SizedBox(height: 10),
                _buildSearchField(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    // DPAD exits are routed by TvTextField itself: down to the first list row,
    // up to the search button.
    final app = AppThemeScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: app.seeAll.panel,
        borderRadius: app.shape.br(11),
        border: Border.all(color: app.seeAll.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 18,
            color: app.fade(app.core.tx, 0.5),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TvTextField(
              controller: _searchController,
              focusNode: _searchFocus,
              style: const TextStyle(fontSize: 13),
              cursorColor: app.seeAll.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search addons',
                hintStyle: TextStyle(color: app.fade(app.core.tx, 0.35)),
              ),
              onSubmitted: (_) => _focusFirstRow(),
              onDownArrow: _focusFirstRow,
              onUpArrow: () => _searchBtnFocus.requestFocus(),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() {
              _searchController.clear();
              _searchOpen = false;
            }),
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: app.fade(app.core.tx, 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_kind == _HubKind.engines) return _buildEngineList();
    switch (_source) {
      case _AddonSource.installed:
        return _buildInstalledList();
      case _AddonSource.official:
      case _AddonSource.community:
        return _buildMarketList();
    }
  }

  Widget _buildInstalledList() {
    if (_installedLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kSeeAllAccent, strokeWidth: 2),
      );
    }
    final items = _installed
        .where((a) => _matchesFilters(types: a.types, name: a.name))
        .toList();
    return Column(
      children: [
        _buildMetadataProviderSetting(),
        Expanded(
          child: items.isEmpty
              ? _emptyState(
                  icon: Icons.extension_outlined,
                  title: _installed.isEmpty ? 'No addons yet' : 'No matches',
                  subtitle: _installed.isEmpty
                      ? 'Add a manifest URL, or install one from Discover.'
                      : 'Try a different type or search.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
                  // DPAD can only move to rows that are BUILT — pre-build far
                  // past the viewport so focus never hits an unbuilt-row wall.
                  scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (_, i) => _InstalledRow(
                    addon: items[i],
                    focusNode: i == 0 ? _firstRowFocus : null,
                    warnDebrid:
                        !_hasDebrid && items[i].resources.contains('stream'),
                    onTap: () => _showOptions(items[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMetadataProviderSetting() {
    final app = AppThemeScope.of(context);
    final providers = _installed
        .where(
          (a) =>
              a.enabled && a.resources.contains('meta') && a.baseUrl.isNotEmpty,
        )
        .toList();
    providers.sort((a, b) {
      final aCinemeta = StremioService.isCinemetaAddon(a);
      final bCinemeta = StremioService.isCinemetaAddon(b);
      if (aCinemeta == bCinemeta) return 0;
      return aCinemeta ? -1 : 1;
    });

    final providerValues = providers
        .map(StremioService.metadataProviderValue)
        .toSet();
    String value;
    if (_metadataProviderPreference ==
        StremioService.automaticMetadataProvider) {
      value = StremioService.automaticMetadataProvider;
    } else if (_metadataProviderPreference != null &&
        providerValues.contains(_metadataProviderPreference)) {
      value = _metadataProviderPreference!;
    } else {
      final cinemeta = providers.where(StremioService.isCinemetaAddon);
      value = cinemeta.isNotEmpty
          ? StremioService.metadataProviderValue(cinemeta.first)
          : StremioService.automaticMetadataProvider;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 4, 24, 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: app.seeAll.panel,
        borderRadius: app.shape.br(13),
        border: Border.all(color: app.seeAll.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Row(
            children: [
              Icon(
                Icons.badge_outlined,
                size: 20,
                color: app.fade(app.seeAll.accent2, 0.9),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Metadata provider',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Used to enrich details from Trakt, Simkl and MDBList.',
                      style: TextStyle(
                        fontSize: 12,
                        color: app.fade(app.core.tx, 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final picker = StremioDropdown<String>(
            value: value,
            focusNode: _metadataFocus,
            isTelevision: _isTv,
            onUpArrowPressed: () => _typeFocus.requestFocus(),
            onDownArrowPressed: () {
              if (_firstRowFocus.context != null) {
                _firstRowFocus.requestFocus();
              }
            },
            options: [
              for (final addon in providers)
                StremioDropdownOption(
                  StremioService.metadataProviderValue(addon),
                  StremioService.isCinemetaAddon(addon)
                      ? '${addon.name} · Recommended'
                      : addon.name,
                ),
              const StremioDropdownOption(
                StremioService.automaticMetadataProvider,
                'Automatic',
              ),
            ],
            onSelected: _setMetadataProvider,
          );
          if (constraints.maxWidth < 500) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: picker),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 14),
              picker,
            ],
          );
        },
      ),
    );
  }

  Future<void> _setMetadataProvider(String value) async {
    final previous = _metadataProviderPreference;
    setState(() => _metadataProviderPreference = value);
    try {
      await _stremio.setMetadataProviderPreference(value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _metadataProviderPreference = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn\'t save metadata provider: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildMarketList() {
    // Compatibility note pinned above BOTH marketplaces (Official/Community):
    // the catalogs list every Stremio addon, but only these four capability
    // families do anything in Debrify.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
          child: _marketCompatNote(),
        ),
        Expanded(child: _buildMarketListBody()),
        // Attribution required by the stremio-addons.net API terms — shown only
        // on the Community list AND only when that source actually served the
        // data (not the legacy fallback, which would be a misattribution).
        if (_source == _AddonSource.community && _marketplace.communityFromNet)
          _communityAttribution(),
      ],
    );
  }

  /// Visible credit link back to stremio-addons.net, required by their API's
  /// attribution terms when we display community-directory data.
  Widget _communityAttribution() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: GestureDetector(
        onTap: () async {
          final uri = Uri.parse('https://stremio-addons.net');
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {
            /* no browser — the label still credits the source */
          }
        },
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Community addons from '),
              TextSpan(
                text: 'stremio-addons.net',
                style: TextStyle(
                  color: kSeeAllAccent,
                  decoration: TextDecoration.underline,
                  decorationColor: kSeeAllAccent.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }

  /// Slim accent-tinted banner: which addon capabilities Debrify supports.
  Widget _marketCompatNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: kSeeAllAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kSeeAllAccent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: kSeeAllAccent.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Works with Debrify: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const TextSpan(
                    text:
                        'catalog, HTTP stream, torrent-scraping and '
                        'subtitle addons. Other types install but add '
                        'nothing here.',
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketListBody() {
    if (_marketLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kSeeAllAccent, strokeWidth: 2),
      );
    }
    if (_marketError != null) {
      return _emptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn\'t load addons',
        subtitle: _marketError!,
        action: _HubActionButton(
          icon: Icons.refresh_rounded,
          label: 'Retry',
          primary: true,
          onTap: () => _loadMarket(_source, force: true),
        ),
      );
    }
    final items = _market
        .where((m) => _matchesFilters(types: m.types, name: m.name))
        .toList();
    if (items.isEmpty) {
      return _emptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        subtitle: 'Try a different type or search.',
      );
    }
    // Assign each FOCUSABLE row (installed rows have no button) a nav index so
    // vertical DPAD can hop row-to-row deterministically.
    final navIndexOf = <int, int>{};
    var focusable = 0;
    for (var i = 0; i < items.length; i++) {
      if (!_isInstalled(items[i])) navIndexOf[i] = focusable++;
    }
    _marketNav.ensure(focusable);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      // See installed list — keep DPAD off the unbuilt wall.
      scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        final m = items[i];
        final navIndex = navIndexOf[i];
        return _MarketRow(
          addon: m,
          installed: _isInstalled(m),
          nav: _marketNav,
          navIndex: navIndex,
          navCount: focusable,
          warnDebrid: !_hasDebrid && m.resources.contains('stream'),
          onInstall: () => _installFromMarket(m, navIndex),
          onConfigure: () => _configureInBrowser(m),
        );
      },
    );
  }

  Widget _buildEngineList() {
    if (_enginesLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kSeeAllAccent, strokeWidth: 2),
      );
    }
    if (_enginesError != null) {
      return _emptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn\'t load engines',
        subtitle: _enginesError!,
        action: _HubActionButton(
          icon: Icons.refresh_rounded,
          label: 'Retry',
          primary: true,
          onTap: _loadEngines,
        ),
      );
    }
    if (_importedEngines.isEmpty && _availableEngines.isEmpty) {
      return _emptyState(
        icon: Icons.travel_explore_rounded,
        title: 'No engines available',
        subtitle: 'Import an engine YAML, or check back after a refresh.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
      children: [
        if (_importedEngines.isNotEmpty) ...[
          _engineSectionHeader('Imported', _importedEngines.length),
          for (var i = 0; i < _importedEngines.length; i++) ...[
            _EngineRow(
              icon: _iconForEngine(_importedEngines[i].icon),
              title: _importedEngines[i].displayName,
              subtitle:
                  'Imported ${_relativeDate(_importedEngines[i].importedAt)}',
              actionLabel: 'Remove',
              danger: true,
              focusNode: i == 0 ? _firstRowFocus : null,
              onTap: () => _deleteEngine(_importedEngines[i]),
            ),
            const SizedBox(height: 14),
          ],
        ],
        if (_availableEngines.isNotEmpty) ...[
          _engineSectionHeader(
            'Available to install',
            _availableEngines.length,
          ),
          for (var i = 0; i < _availableEngines.length; i++) ...[
            _EngineRow(
              icon: _iconForEngine(_availableEngines[i].icon),
              title: _availableEngines[i].displayName,
              subtitle: _availableEngines[i].description,
              actionLabel: 'Install',
              primary: true,
              focusNode: (_importedEngines.isEmpty && i == 0)
                  ? _firstRowFocus
                  : null,
              onTap: () => _installEngine(_availableEngines[i]),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ],
    );
  }

  Widget _engineSectionHeader(String label, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 0, 12),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: kSeeAllAccent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: kSeeAllAccent2,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForEngine(String? name) {
    switch (name) {
      case 'sailing':
        return Icons.sailing_rounded;
      case 'storage':
      case 'database':
        return Icons.storage_rounded;
      case 'movie':
      case 'movie_creation':
        return Icons.movie_rounded;
      case 'tv':
        return Icons.tv_rounded;
      case 'cloud':
        return Icons.cloud_rounded;
      case 'search':
        return Icons.search_rounded;
      case 'public':
        return Icons.public_rounded;
      default:
        return Icons.extension_rounded;
    }
  }

  String _relativeDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.white.withValues(alpha: 0.25)),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
            if (action != null) ...[const SizedBox(height: 18), action],
          ],
        ),
      ),
    );
  }
}

// ── Rows ─────────────────────────────────────────────────────────────────────

/// Focus wrapper giving a card the purple DPAD ring + activate-key handling.
class _FocusCard extends StatefulWidget {
  final VoidCallback onTap;
  final Widget Function(bool focused) builder;
  final FocusNode? focusNode;
  const _FocusCard({
    required this.onTap,
    required this.builder,
    this.focusNode,
  });

  @override
  State<_FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<_FocusCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) _centerInScrollable(context);
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateKey(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        // A small scale pop makes DPAD focus feel tactile. Compositor-only
        // transform on one layer — cheap even on weak TV GPUs.
        child: AnimatedScale(
          scale: _focused ? 1.008 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: widget.builder(_focused),
        ),
      ),
    );
  }
}

/// Flat, borderless Stremio-style card. The border slot is a CONSTANT 2px (a
/// changing width feeds into Container's layout padding and reflows the list —
/// the "shake"); unfocused it's transparent so the card reads clean and flat.
const Color _kCardBg = Color(0xFF191B28);

BoxDecoration _cardDecoration(bool focused) => BoxDecoration(
  color: _kCardBg,
  borderRadius: BorderRadius.circular(12),
  border: Border.all(
    width: 2,
    color: focused ? kSeeAllAccent : Colors.transparent,
  ),
);

class _InstalledRow extends StatelessWidget {
  final StremioAddon addon;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool warnDebrid;
  const _InstalledRow({
    required this.addon,
    required this.onTap,
    this.focusNode,
    this.warnDebrid = false,
  });

  @override
  Widget build(BuildContext context) {
    final chevron = Icon(
      Icons.chevron_right_rounded,
      size: 26,
      color: Colors.white.withValues(alpha: 0.3),
    );
    return _FocusCard(
      onTap: onTap,
      focusNode: focusNode,
      builder: (focused) => LayoutBuilder(
        builder: (context, c) {
          // On a phone-width card the logo + status pill + chevron leave the
          // info column too narrow (name/type truncate, chips wrap into a tall
          // stack). Below the breakpoint, keep only the logo + title + status
          // in a header row and let the type/chips/description use the full
          // width beneath. Wide (tablet/desktop/TV) keeps the single-row look.
          final narrow = c.maxWidth < 480;
          final meta = _AddonMeta(
            types: addon.types,
            resources: addon.resources,
            description: addon.description,
            warnDebrid: warnDebrid,
          );
          return Container(
            decoration: _cardDecoration(focused),
            padding: EdgeInsets.symmetric(
              horizontal: narrow ? 16 : 22,
              vertical: narrow ? 16 : 20,
            ),
            child: narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Compact logo + version-under-name: the header row
                          // also carries the pill and chevron, so every fixed
                          // pixel here comes straight out of the name's width.
                          _addonLogo(null, size: 44),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _AddonTitleLine(
                              name: addon.name,
                              version: addon.version,
                              stacked: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          _StatusPill(enabled: addon.enabled),
                          const SizedBox(width: 4),
                          chevron,
                        ],
                      ),
                      const SizedBox(height: 14),
                      meta,
                    ],
                  )
                : Row(
                    children: [
                      _addonLogo(null),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _AddonInfo(
                          name: addon.name,
                          version: addon.version,
                          types: addon.types,
                          resources: addon.resources,
                          description: addon.description,
                          warnDebrid: warnDebrid,
                        ),
                      ),
                      const SizedBox(width: 16),
                      _StatusPill(enabled: addon.enabled),
                      const SizedBox(width: 8),
                      chevron,
                    ],
                  ),
          );
        },
      ),
    );
  }
}

/// Shared name/version/types/description column, matching the Stremio addons
/// screen: title with a small muted version beside it, muted type line,
/// capability chips (what the addon actually provides), then a two-line
/// description.
class _AddonInfo extends StatelessWidget {
  final String name;
  final String? version;
  final List<String> types;
  final List<String> resources;
  final String? description;

  /// Show a "Needs debrid" hint — this addon provides streams but no debrid
  /// provider is configured, so its torrents can't play (debrify has no P2P).
  final bool warnDebrid;

  const _AddonInfo({
    required this.name,
    required this.version,
    required this.types,
    required this.resources,
    required this.description,
    this.warnDebrid = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _AddonTitleLine(name: name, version: version),
        const SizedBox(height: 4),
        _AddonMeta(
          types: types,
          resources: resources,
          description: description,
          warnDebrid: warnDebrid,
        ),
      ],
    );
  }
}

/// The name + muted version, on one baseline-aligned line. Extracted so the
/// narrow card layout can hoist it into a header row (beside the logo / status)
/// while the rest of the info flows full-width below.
class _AddonTitleLine extends StatelessWidget {
  final String name;
  final String? version;

  /// When true, the version sits on its own line *under* the name instead of
  /// beside it — the narrow header row can't afford to give the version a
  /// fixed slice of the name's width.
  final bool stacked;

  const _AddonTitleLine({
    required this.name,
    required this.version,
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) {
    final nameText = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
    final versionText = (version != null && version!.isNotEmpty)
        ? Text(
            'v.$version',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          )
        : null;

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          nameText,
          if (versionText != null) ...[const SizedBox(height: 2), versionText],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(child: nameText),
        if (versionText != null) ...[const SizedBox(width: 10), versionText],
      ],
    );
  }
}

/// The type line, capability chips and description — everything below the
/// title. Kept separate so the narrow layout can give it the full card width
/// (chips no longer wrap into a tall stack in a squeezed column).
class _AddonMeta extends StatelessWidget {
  final List<String> types;
  final List<String> resources;
  final String? description;
  final bool warnDebrid;
  const _AddonMeta({
    required this.types,
    required this.resources,
    required this.description,
    this.warnDebrid = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          types.isEmpty ? 'Addon' : types.map(_capitalize).join(' & '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.42),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (_capabilities(resources).isNotEmpty || warnDebrid) ...[
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final cap in _capabilities(resources))
                _CapabilityChip(label: cap.$1, highlight: cap.$2),
              if (warnDebrid) const _WarningChip(label: 'Needs debrid'),
            ],
          ),
        ],
        if (description != null && description!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            description!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _MarketRow extends StatelessWidget {
  final MarketplaceAddon addon;
  final bool installed;
  final VoidCallback onInstall;
  final VoidCallback onConfigure;

  /// Row-to-row DPAD navigation. [navIndex] is this row's slot in [nav] (null
  /// for installed rows, which aren't focusable); [navCount] is the total.
  final _RowNav nav;
  final int? navIndex;
  final int navCount;
  final bool warnDebrid;

  const _MarketRow({
    required this.addon,
    required this.installed,
    required this.onInstall,
    required this.onConfigure,
    required this.nav,
    required this.navIndex,
    required this.navCount,
    this.warnDebrid = false,
  });

  /// DOWN → next row's first button (always handled, so it never escapes the
  /// list sideways). UP → previous row's first button, or fall through to the
  /// filter bar when already at the top.
  bool _onDown() {
    nav.focus((navIndex ?? 0) + 1);
    return true;
  }

  bool _onUp() {
    final i = navIndex ?? 0;
    if (i == 0) return false; // let default traversal reach the filter bar
    nav.focus(i - 1);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Same responsive split as the installed card: below the breakpoint,
        // logo + title share a header row, the info flows full-width, and the
        // Install/Configure buttons drop to their own row (where they get room
        // instead of squeezing the info column).
        final narrow = c.maxWidth < 480;
        final meta = _AddonMeta(
          types: addon.types,
          resources: addon.resources,
          description: addon.description,
          warnDebrid: warnDebrid,
        );
        return Container(
          decoration: _cardDecoration(false),
          padding: EdgeInsets.symmetric(
            horizontal: narrow ? 16 : 22,
            vertical: narrow ? 16 : 20,
          ),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _addonLogo(addon.logo, size: 44),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _AddonTitleLine(
                            name: addon.name,
                            version: addon.version,
                            stacked: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    meta,
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _buildActions(),
                    ),
                  ],
                )
              : Row(
                  children: [
                    _addonLogo(addon.logo),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _AddonInfo(
                        name: addon.name,
                        version: addon.version,
                        types: addon.types,
                        resources: addon.resources,
                        description: addon.description,
                        warnDebrid: warnDebrid,
                      ),
                    ),
                    const SizedBox(width: 16),
                    _buildActions(),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildActions() {
    if (installed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: kSeeAllAccent2.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 6),
          Text(
            'Installed',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    // configurationRequired: config is mandatory, so there's no plain Install.
    // configurable (optional): offer both Install and Configure.
    // The row's FIRST button carries this row's nav node so DOWN/UP land on it.
    final primaryNode = navIndex != null ? nav.nodeAt(navIndex!) : null;
    final buttons = <Widget>[];
    if (!addon.configurationRequired) {
      buttons.add(
        _MarketButton(
          label: 'Install',
          primary: true,
          focusNode: primaryNode,
          onArrowDown: _onDown,
          onArrowUp: _onUp,
          onTap: onInstall,
        ),
      );
    }
    if (addon.configurationRequired || addon.configurable) {
      buttons.add(
        _MarketButton(
          label: 'Configure',
          focusNode: buttons.isEmpty ? primaryNode : null,
          onArrowDown: _onDown,
          onArrowUp: _onUp,
          onTap: onConfigure,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          buttons[i],
        ],
      ],
    );
  }
}

/// A stadium Install/Configure button matching the Stremio addons screen:
/// primary = solid accent fill, secondary = quiet outline. Constant 2px border
/// so focus never changes the button's size (no reflow shake).
class _MarketButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final FocusNode? focusNode;

  /// Return true if the arrow was consumed (focus moved / deliberately held).
  final bool Function()? onArrowUp;
  final bool Function()? onArrowDown;

  const _MarketButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.focusNode,
    this.onArrowUp,
    this.onArrowDown,
  });

  @override
  State<_MarketButton> createState() => _MarketButtonState();
}

class _MarketButtonState extends State<_MarketButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final Color fill;
    final Color borderColor;
    // The label/ring sit ON the accent fill when primary; the quiet variant sits
    // on the (untokenised) card, so its whites stay literal.
    final Color ink;
    if (widget.primary) {
      fill = _focused ? app.seeAll.accent2 : app.seeAll.accent;
      ink = app.inkOn(app.seeAll.accent);
      borderColor = _focused ? ink : Colors.transparent;
    } else {
      fill = _focused
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.transparent;
      borderColor = _focused
          ? Colors.white
          : Colors.white.withValues(alpha: 0.22);
      ink = Colors.white;
    }
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) _centerInScrollable(context);
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (isActivateKey(event.logicalKey)) {
          if (event is KeyDownEvent) widget.onTap();
          return KeyEventResult.handled;
        }
        // Vertical DPAD hops rows (Install↔Install, or Install→Configure-only) —
        // horizontal is left to default traversal (Install ↔ Configure in-row).
        if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
            widget.onArrowDown != null) {
          return widget.onArrowDown!()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
            widget.onArrowUp != null) {
          return widget.onArrowUp!()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: app.shape.br(24),
              border: Border.all(width: 2, color: borderColor),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A themed torrent-engine row (imported or available). Whole card is the tap
/// target — matching the classic engine screen — with a trailing action pill.
class _EngineRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String actionLabel;
  final bool primary;
  final bool danger;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  const _EngineRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    this.primary = false,
    this.danger = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return _FocusCard(
      onTap: onTap,
      focusNode: focusNode,
      builder: (focused) => Container(
        decoration: _cardDecoration(focused),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: kSeeAllAccent2, size: 30),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            _EngineActionPill(
              label: actionLabel,
              primary: primary,
              danger: danger,
            ),
          ],
        ),
      ),
    );
  }
}

/// A non-focusable label pill inside an engine row (the whole row is the button;
/// this just states the action). Install = accent, Remove = danger outline.
class _EngineActionPill extends StatelessWidget {
  final String label;
  final bool primary;
  final bool danger;
  const _EngineActionPill({
    required this.label,
    this.primary = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final Color fill;
    final Color border;
    final Color text;
    if (danger) {
      fill = Colors.transparent;
      border = const Color(0xFFEF4444).withValues(alpha: 0.5);
      text = const Color(0xFFEF4444);
    } else if (primary) {
      fill = app.seeAll.accent;
      border = Colors.transparent;
      text = app.inkOn(app.seeAll.accent);
    } else {
      fill = Colors.transparent;
      border = Colors.white.withValues(alpha: 0.22);
      text = Colors.white;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: app.shape.br(24),
        border: Border.all(width: 2, color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Addon logo, Stremio-style: the image (or a plain muted puzzle piece) sits
/// directly on the card — no tinted chip behind it.
Widget _addonLogo(String? url, {double size = 64}) => SizedBox(
  width: size,
  height: size,
  child: (url != null && url.isNotEmpty)
      ? ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            memCacheWidth: 192,
            errorWidget: (_, __, ___) => Icon(
              Icons.extension_rounded,
              color: Colors.white38,
              size: size * 0.72,
            ),
          ),
        )
      : Icon(Icons.extension_rounded, color: Colors.white38, size: size * 0.72),
);

class _StatusPill extends StatelessWidget {
  final bool enabled;
  const _StatusPill({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? kSeeAllAccent2
        : Colors.white.withValues(alpha: 0.4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        enabled ? 'ON' : 'OFF',
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ── Options bottom sheet ─────────────────────────────────────────────────────

class _AddonOptionsSheet extends StatelessWidget {
  final StremioAddon addon;
  final VoidCallback onToggle;
  final VoidCallback onUpdate;
  final VoidCallback onDetails;
  final VoidCallback onRemove;

  const _AddonOptionsSheet({
    required this.addon,
    required this.onToggle,
    required this.onUpdate,
    required this.onDetails,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: app.fade(app.core.tx, 0.2),
                borderRadius: app.shape.br(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                addon.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _OptionTile(
              autofocus: true,
              icon: addon.enabled
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              label: addon.enabled ? 'Disable' : 'Enable',
              onTap: onToggle,
            ),
            _OptionTile(
              icon: Icons.sync_rounded,
              label: 'Update',
              onTap: onUpdate,
            ),
            _OptionTile(
              icon: Icons.info_outline_rounded,
              label: 'View details',
              onTap: onDetails,
            ),
            _OptionTile(
              icon: Icons.delete_outline_rounded,
              label: 'Remove',
              danger: true,
              onTap: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool autofocus;
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.autofocus = false,
  });

  @override
  State<_OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<_OptionTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final color = widget.danger ? const Color(0xFFEF4444) : app.core.tx;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateKey(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: _focused
                ? app.fade(app.seeAll.accent, 0.14)
                : Colors.transparent,
            borderRadius: app.shape.br(11),
            border: Border.all(
              color: _focused ? app.seeAll.accent : Colors.transparent,
              width: _focused ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 20, color: color),
              const SizedBox(width: 14),
              Text(
                widget.label,
                style: TextStyle(
                  color: color,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Buttons & dialog chrome ──────────────────────────────────────────────────

/// A pill button that matches the Discover chrome: panel fill, purple focus ring;
/// [primary] fills with the accent tint.
class _HubActionButton extends StatefulWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool primary;
  final FocusNode? focusNode;

  /// Fill the parent's width with centred content (narrow filter bar rows)
  /// instead of hugging the icon+label.
  final bool expand;

  const _HubActionButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.primary = false,
    this.focusNode,
    this.expand = false,
  });

  @override
  State<_HubActionButton> createState() => _HubActionButtonState();
}

class _HubActionButtonState extends State<_HubActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // Primary = solid accent (like Stremio's filled "Add addon"); others sit on
    // the quiet panel fill. Border is a constant 2px — width changes feed into
    // Container's layout and shake the whole filter row on focus moves.
    final app = AppThemeScope.of(context);
    final Color fill;
    final Color borderColor;
    // Primary's label/ring sit ON the accent fill; the quiet variant's sit on
    // the panel fill, which is page ink's ground.
    final Color ink;
    if (widget.primary) {
      fill = _focused ? app.seeAll.accent2 : app.seeAll.accent;
      ink = app.inkOn(app.seeAll.accent);
      borderColor = _focused ? ink : Colors.transparent;
    } else {
      fill = app.seeAll.panel;
      borderColor = _focused ? app.seeAll.accent : app.seeAll.line;
      ink = app.core.tx;
    }
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateKey(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: widget.label == null ? 10 : 16,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: app.shape.br(11),
              border: Border.all(width: 2, color: borderColor),
            ),
            child: Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 17, color: ink),
                if (widget.label != null) ...[
                  const SizedBox(width: 7),
                  Text(
                    widget.label!,
                    style: TextStyle(
                      color: ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
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

/// A dark-glass dialog matching the hub theme (AlertDialog styling gets awkward
/// against the purple palette, so we roll a minimal one).
class _HubDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;
  const _HubDialog({
    required this.title,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Dialog(
      backgroundColor: app.seeAll.panel,
      shape: RoundedRectangleBorder(
        borderRadius: app.shape.br(18),
        side: BorderSide(color: app.seeAll.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            content,
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final a in actions) ...[a, const SizedBox(width: 8)],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HubDialogButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool danger;
  const _HubDialogButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.danger = false,
  });

  @override
  State<_HubDialogButton> createState() => _HubDialogButtonState();
}

class _HubDialogButtonState extends State<_HubDialogButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    Color fill;
    Color textColor;
    if (widget.danger) {
      fill = const Color(0xFFEF4444).withValues(alpha: 0.16);
      textColor = const Color(0xFFEF4444);
    } else if (widget.primary) {
      fill = app.fade(app.seeAll.accent, 0.20);
      textColor = app.core.tx;
    } else {
      fill = Colors.transparent;
      textColor = app.fade(app.core.tx, 0.75);
    }
    final borderColor = _focused
        ? app.seeAll.accent
        : (widget.primary || widget.danger
              ? app.seeAll.accentBorder
              : app.seeAll.line);
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateKey(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: app.shape.br(10),
            // Constant width — see _HubActionButton (focus resize = shake).
            border: Border.all(
              width: 2,
              color: widget.danger && !_focused
                  ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                  : borderColor,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: textColor,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// A grow-only pool of focus nodes, one per focusable marketplace row, used to
/// hop DPAD focus row-to-row deterministically. Grow-only (never disposes mid-
/// session) so a shrinking filtered list can't dispose a node that holds focus.
class _RowNav {
  final List<FocusNode> _nodes = [];

  void ensure(int n) {
    while (_nodes.length < n) {
      _nodes.add(FocusNode(debugLabel: 'market-row-${_nodes.length}'));
    }
  }

  FocusNode? nodeAt(int i) => (i >= 0 && i < _nodes.length) ? _nodes[i] : null;

  /// Focus row [i] if it exists; returns whether it did.
  bool focus(int i) {
    final node = nodeAt(i);
    if (node == null) return false;
    node.requestFocus();
    return true;
  }

  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    _nodes.clear();
  }
}

/// Map a manifest's `resources` to user-facing capability labels, in importance
/// order. The `bool` is "highlight" — Streams is what Debrify is built around,
/// so it's the accented chip. Unknown/irrelevant resources are dropped.
List<(String, bool)> _capabilities(List<String> resources) {
  const order = <String, (String, bool)>{
    'stream': ('Streams', true),
    'catalog': ('Catalog', false),
    'meta': ('Metadata', false),
    'subtitles': ('Subtitles', false),
    'addon_catalog': ('Addon list', false),
  };
  final out = <(String, bool)>[];
  for (final entry in order.entries) {
    if (resources.contains(entry.key)) out.add(entry.value);
  }
  return out;
}

/// A small pill stating one thing an addon provides (Streams / Catalog / …).
class _CapabilityChip extends StatelessWidget {
  final String label;
  final bool highlight;
  const _CapabilityChip({required this.label, required this.highlight});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? kSeeAllAccent.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: highlight
              ? kSeeAllAccentBorder
              : Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: highlight
              ? kSeeAllAccent2
              : Colors.white.withValues(alpha: 0.7),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// An amber caveat chip (e.g. "Needs debrid") — a heads-up, not a capability.
class _WarningChip extends StatelessWidget {
  final String label;
  const _WarningChip({required this.label});

  static const Color _amber = Color(0xFFF6B94A);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline_rounded, size: 11, color: _amber),
          const SizedBox(width: 4),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: _amber,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Scroll the focused row toward the vertical centre of its list. The framework
/// only nudges a newly-focused item to the nearest edge (so DPAD-down parks it
/// at the bottom); this keeps it centred instead. [ensureVisible] clamps to the
/// valid scroll range, so the first rows still rest at the top and the last at
/// the bottom — only the middle is actually centred.
void _centerInScrollable(BuildContext context) {
  final scrollable = Scrollable.maybeOf(context);
  if (scrollable == null) return;
  Scrollable.ensureVisible(
    context,
    alignment: 0.5,
    alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
  );
}
