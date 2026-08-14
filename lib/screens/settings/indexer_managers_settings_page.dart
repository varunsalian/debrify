import 'package:flutter/material.dart';

import '../../models/indexer_manager_config.dart';
import '../../services/indexer_manager_service.dart';
import '../../services/profiles/profile_async_authorization.dart';
import '../../services/storage_service.dart';
import '../../services/torrent_service.dart';
import '../../services/analytics_service.dart';
import '../../utils/platform_util.dart';
import '../../widgets/tv_text_field.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';
import '../../models/profiles/profile_policy.dart';

/// Focused IconButtons get the accent outline + lit fill — the stock
/// Material focus overlay is invisible on the dark settings theme (TV DPAD).
/// TOP-LEVEL final, so it cannot read a BuildContext: this one keeps the
/// `kSettings*` constants until it becomes a function of context.
final ButtonStyle _focusableIconStyle = ButtonStyle(
  backgroundColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused) ? kSettingsPanel2 : null,
  ),
  side: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? const BorderSide(color: kSettingsAccent)
        : null,
  ),
);

class IndexerManagersSettingsPage extends StatefulWidget {
  const IndexerManagersSettingsPage({super.key});

  @override
  State<IndexerManagersSettingsPage> createState() =>
      _IndexerManagersSettingsPageState();
}

class _IndexerManagersSettingsPageState
    extends State<IndexerManagersSettingsPage> {
  List<IndexerManagerConfig> _configs = [];
  bool _loading = true;
  final FocusNode _addButtonFocus = FocusNode(debugLabel: 'indexer-add-button');
  final FocusNode _firstRowFocus = FocusNode(debugLabel: 'indexer-first-row');

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('indexer_managers_settings');
    _loadConfigs();
  }

  @override
  void dispose() {
    _addButtonFocus.dispose();
    _firstRowFocus.dispose();
    super.dispose();
  }

  Future<void> _loadConfigs() async {
    final configs = await StorageService.getIndexerManagerConfigs(
      forSettings: true,
    );
    if (!mounted) return;
    setState(() {
      _configs = configs;
      _loading = false;
    });
    // On TV, land DPAD focus on the first interactive element so users
    // aren't stranded (the first row's switch, or Add when the list is
    // empty).
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Only a bare FocusScopeNode as primary focus means DPAD is
        // stranded — don't steal focus the user already placed somewhere.
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        (_configs.isEmpty ? _addButtonFocus : _firstRowFocus).requestFocus();
      });
    }
  }

  Future<List<IndexerManagerConfig>> _saveConfigs(
    List<IndexerManagerConfig> configs, {
    ProfileAsyncAuthorization? authorization,
  }) async {
    Future<List<IndexerManagerConfig>> save() =>
        StorageService.setIndexerManagerConfigs(configs);
    final List<IndexerManagerConfig> saved;
    if (authorization == null) {
      saved = await save();
    } else {
      saved = await authorization.runIfCurrent(save);
    }
    if (mounted) setState(() => _configs = saved);
    return saved;
  }

  Future<void> _toggleEnabled(IndexerManagerConfig config, bool enabled) async {
    if (config.connectionReadOnly) return;
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.torrentSearch,
    );
    if (!mounted) return;
    final updated = config.copyWith(enabled: enabled);
    final canonical = await _replaceConfig(
      updated,
      authorization: authorization,
    );
    await _setEngineEnabled(canonical.engineId, enabled);
  }

  Future<IndexerManagerConfig> _replaceConfig(
    IndexerManagerConfig updated, {
    ProfileAsyncAuthorization? authorization,
  }) async {
    final configs = _configs
        .map((config) => config.id == updated.id ? updated : config)
        .toList();
    final saved = await _saveConfigs(configs, authorization: authorization);
    final resourceId = updated.connectionResourceId;
    if (resourceId != null) {
      return saved.singleWhere(
        (config) => config.connectionResourceId == resourceId,
      );
    }
    final idMatch = saved.where((config) => config.id == updated.id);
    if (idMatch.length == 1) return idMatch.single;
    return saved.singleWhere(
      (config) =>
          config.type == updated.type &&
          config.normalizedBaseUrl == updated.normalizedBaseUrl &&
          config.apiKey == updated.apiKey &&
          config.displayName == updated.displayName,
    );
  }

  Future<void> _deleteConfig(IndexerManagerConfig config) async {
    if (config.connectionReadOnly) return;
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.torrentSearch,
    );
    if (!mounted) return;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Engine'),
        content: Text('Remove ${config.displayName} from torrent search?'),
        actions: [
          _FocusRing(
            borderRadius: 12,
            child: TextButton(
              // TV: seed DPAD focus inside the dialog (BACK still dismisses).
              autofocus: PlatformUtil.isTelevision,
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ),
          _FocusRing(
            borderRadius: 12,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;
    await _saveConfigs(
      _configs.where((item) => item.id != config.id).toList(),
      authorization: authorization,
    );
    // The deleted row unmounted under the focused Delete button — reseed
    // DPAD focus on a surviving row (or Add when the list empties).
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (_configs.isEmpty ? _addButtonFocus : _firstRowFocus).requestFocus();
      });
    }
  }

  Future<void> _openEditor([IndexerManagerConfig? config]) async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.torrentSearch,
    );
    if (!mounted) return;
    final result = await showDialog<IndexerManagerConfig>(
      context: context,
      builder: (context) => _IndexerManagerEditorDialog(config: config),
    );
    if (result == null || !mounted) return;

    final IndexerManagerConfig canonical;
    if (config == null) {
      final priorResourceIds = <String>{
        for (final item in _configs)
          if (item.connectionResourceId != null) item.connectionResourceId!,
      };
      final saved = await _saveConfigs([
        ..._configs,
        result,
      ], authorization: authorization);
      canonical = saved.singleWhere(
        (item) =>
            item.id == result.id ||
            (item.connectionResourceId != null &&
                !priorResourceIds.contains(item.connectionResourceId)),
      );
    } else {
      canonical = await _replaceConfig(result, authorization: authorization);
    }
    await _setEngineEnabled(canonical.engineId, canonical.enabled);
  }

  Future<void> _setEngineEnabled(String engineId, bool enabled) async {
    // A collection write rotates the profile authorization revision, so the
    // capability captured before the editor opened is intentionally stale.
    // Capture the post-save authority before publishing the engine toggle.
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.torrentSearch,
    );
    if (authorization == null) {
      await TorrentService.setEngineEnabled(engineId, enabled);
    } else {
      await authorization.runIfCurrent(
        () => TorrentService.setEngineEnabled(engineId, enabled),
      );
    }
  }

  Future<void> _testConfig(IndexerManagerConfig config) async {
    final t = AppThemeScope.of(context).settings;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Testing ${config.displayName}...')),
    );
    final result = await IndexerManagerService.testConnection(config);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? t.success : t.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'Indexer Managers',
      actions: [
        IconButton(
          focusNode: _addButtonFocus,
          style: _focusableIconStyle,
          onPressed: _loading ? null : () => _openEditor(),
          icon: const Icon(Icons.add_rounded),
          tooltip: 'Add engine',
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kSettingsMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(context),
                      const SizedBox(height: 16),
                      if (_configs.isEmpty)
                        _buildEmptyState(context)
                      else
                        ..._configs.map(_buildConfigTile),
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButton: _loading ? null : _buildAddEngineButton(context),
    );
  }

  Widget? _buildAddEngineButton(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final isCompact = MediaQuery.sizeOf(context).width < 720;

    if (isCompact) return null;

    // Ring and label both sit ON the accent-filled FAB, so both take
    // on-accent ink — an accent ring (and the stock focus overlay) is
    // invisible against the fill (TV DPAD), and so is a white one once the
    // theme's accent is itself light.
    final onAccent = app.inkOn(t.accent);
    return _FocusRing(
      borderRadius: 16,
      color: onAccent,
      child: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: t.accent,
        foregroundColor: onAccent,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Engine'),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return const SettingsPageHeader(
      icon: Icons.manage_search_rounded,
      title: 'Indexer Managers',
      subtitle:
          'Connect public or private indexers through Jackett and Prowlarr. Enabled engines appear in the torrent search source picker.',
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.search_off_rounded, size: 40, color: t.dim2),
            const SizedBox(height: 12),
            Text(
              'No indexer managers yet',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: app.core.tx),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a reachable Jackett or Prowlarr server to search its indexers directly from Debrify.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: t.dim),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigTile(IndexerManagerConfig config) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final theme = Theme.of(context);
    final bool isFirst = _configs.isNotEmpty && config.id == _configs.first.id;
    final icon = Icon(
      config.type == IndexerManagerType.prowlarr
          ? Icons.hub_rounded
          : Icons.manage_search_rounded,
      color: t.dim,
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          config.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: theme.textTheme.titleMedium?.copyWith(color: app.core.tx),
        ),
        const SizedBox(height: 2),
        Text(
          config.credentialsRedacted
              ? '${config.type.label} • Shared connection • credentials hidden'
              : '${config.type.label} • ${config.normalizedBaseUrl}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
        ),
      ],
    );
    final controls = Wrap(
      spacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Snap accent ring so DPAD focus on the switch is visible on TV.
        _FocusRing(
          borderRadius: 20,
          child: Switch(
            focusNode: isFirst ? _firstRowFocus : null,
            value: config.enabled,
            onChanged: config.connectionReadOnly
                ? null
                : (value) => _toggleEnabled(config, value),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          style: _focusableIconStyle,
          onPressed: config.connectionReadOnly
              ? null
              : () => _testConfig(config),
          icon: const Icon(Icons.network_check_rounded),
          tooltip: 'Test connection',
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          style: _focusableIconStyle,
          onPressed: config.connectionReadOnly
              ? null
              : () => _openEditor(config),
          icon: const Icon(Icons.edit_rounded),
          tooltip: 'Edit',
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          style: _focusableIconStyle,
          onPressed: config.connectionReadOnly
              ? null
              : () => _deleteConfig(config),
          icon: const Icon(Icons.delete_outline_rounded),
          tooltip: 'Delete',
        ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 520;
            final titleRow = Row(
              children: [
                icon,
                const SizedBox(width: 12),
                Expanded(child: details),
              ],
            );

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  titleRow,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: controls),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: titleRow),
                const SizedBox(width: 12),
                controls,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IndexerManagerEditorDialog extends StatefulWidget {
  final IndexerManagerConfig? config;

  const _IndexerManagerEditorDialog({this.config});

  @override
  State<_IndexerManagerEditorDialog> createState() =>
      _IndexerManagerEditorDialogState();
}

class _IndexerManagerEditorDialogState
    extends State<_IndexerManagerEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _jackettIndexerController;
  late final TextEditingController _categoriesController;
  late final TextEditingController _timeoutController;
  late final FocusNode _nameFocusNode;
  late final FocusNode _urlFocusNode;
  late final FocusNode _apiKeyFocusNode;
  late final FocusNode _jackettIndexerFocusNode;
  late final FocusNode _categoriesFocusNode;
  late final FocusNode _timeoutFocusNode;
  late IndexerManagerType _type;
  late int _maxResults;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    _type = config?.type ?? IndexerManagerType.jackett;
    _maxResults = config?.maxResults ?? 50;
    _enabled = config?.enabled ?? true;
    _nameController = TextEditingController(text: config?.name ?? '');
    _urlController = TextEditingController(text: config?.baseUrl ?? '');
    _apiKeyController = TextEditingController(text: config?.apiKey ?? '');
    _jackettIndexerController = TextEditingController(
      text: config?.jackettIndexerId ?? 'all',
    );
    _categoriesController = TextEditingController(
      text: config?.categories.join(',') ?? '',
    );
    _timeoutController = TextEditingController(
      text: '${config?.timeoutSeconds ?? 20}',
    );
    _nameFocusNode = FocusNode(debugLabel: 'indexer-name');
    _urlFocusNode = FocusNode(debugLabel: 'indexer-url');
    _apiKeyFocusNode = FocusNode(debugLabel: 'indexer-api-key');
    _jackettIndexerFocusNode = FocusNode(debugLabel: 'indexer-jackett-id');
    _categoriesFocusNode = FocusNode(debugLabel: 'indexer-categories');
    _timeoutFocusNode = FocusNode(debugLabel: 'indexer-timeout');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _apiKeyController.dispose();
    _jackettIndexerController.dispose();
    _categoriesController.dispose();
    _timeoutController.dispose();
    _nameFocusNode.dispose();
    _urlFocusNode.dispose();
    _apiKeyFocusNode.dispose();
    _jackettIndexerFocusNode.dispose();
    _categoriesFocusNode.dispose();
    _timeoutFocusNode.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final config = widget.config;
    final categories = _categoriesController.text
        .split(',')
        .map((item) => int.tryParse(item.trim()))
        .whereType<int>()
        .toList();

    Navigator.of(context).pop(
      IndexerManagerConfig(
        id: config?.id ?? IndexerManagerConfig.generateId(),
        name: _nameController.text.trim().isEmpty
            ? _type.label
            : _nameController.text.trim(),
        type: _type,
        baseUrl: _urlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        enabled: _enabled,
        maxResults: _maxResults,
        timeoutSeconds:
            int.tryParse(_timeoutController.text.trim())?.clamp(5, 600) ?? 20,
        jackettIndexerId: _jackettIndexerController.text.trim().isEmpty
            ? 'all'
            : _jackettIndexerController.text.trim(),
        categories: categories,
        connectionResourceId: config?.connectionResourceId,
        connectionResourceRevision: config?.connectionResourceRevision,
        connectionReadOnly: config?.connectionReadOnly ?? false,
        credentialsRedacted: config?.credentialsRedacted ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dialogWidth = (size.width - 32).clamp(320.0, 560.0).toDouble();
    final dialogMaxHeight = (size.height - 48).clamp(420.0, 720.0).toDouble();
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogMaxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Text(
                widget.config == null ? 'Add Engine' : 'Edit Engine',
                style: theme.textTheme.headlineSmall,
              ),
            ),
            Flexible(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<IndexerManagerType>(
                        value: _type,
                        // TV: seed DPAD focus on the first control (not a
                        // text field — that would pop the soft keyboard).
                        autofocus: PlatformUtil.isTelevision,
                        decoration: const InputDecoration(labelText: 'Type'),
                        isExpanded: true,
                        items: IndexerManagerType.values
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(type.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _type = value);
                        },
                      ),
                      const SizedBox(height: 14),
                      TvTextField(
                        controller: _nameController,
                        focusNode: _nameFocusNode,
                        decoration: _engineFieldDecoration(
                          context,
                          const InputDecoration(labelText: 'Name'),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),
                      TvTextField(
                        controller: _urlController,
                        focusNode: _urlFocusNode,
                        decoration: _engineFieldDecoration(
                          context,
                          const InputDecoration(
                            labelText: 'Base URL',
                            hintText: 'http://localhost:9117',
                          ),
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          final uri = Uri.tryParse(text);
                          if (uri == null ||
                              !uri.hasScheme ||
                              uri.host.isEmpty) {
                            return 'Enter a valid URL';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TvTextField(
                        controller: _apiKeyController,
                        focusNode: _apiKeyFocusNode,
                        decoration: _engineFieldDecoration(
                          context,
                          const InputDecoration(labelText: 'API key'),
                        ),
                        obscureText: true,
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'API key is required';
                          }
                          return null;
                        },
                      ),
                      if (_type == IndexerManagerType.jackett) ...[
                        const SizedBox(height: 14),
                        TvTextField(
                          controller: _jackettIndexerController,
                          focusNode: _jackettIndexerFocusNode,
                          decoration: _engineFieldDecoration(
                            context,
                            const InputDecoration(
                              labelText: 'Jackett indexer ID',
                              hintText: 'all',
                            ),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                      ],
                      const SizedBox(height: 14),
                      TvTextField(
                        controller: _categoriesController,
                        focusNode: _categoriesFocusNode,
                        decoration: _engineFieldDecoration(
                          context,
                          const InputDecoration(
                            labelText: 'Categories',
                            hintText: '2000,5000',
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        value: _maxResults,
                        decoration: const InputDecoration(
                          labelText: 'Max results',
                        ),
                        isExpanded: true,
                        items: const [25, 50, 100, 200]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text('$value'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _maxResults = value);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      TvTextField(
                        controller: _timeoutController,
                        focusNode: _timeoutFocusNode,
                        decoration: _engineFieldDecoration(
                          context,
                          const InputDecoration(
                            labelText: 'Timeout seconds',
                            hintText: '20 (5–600)',
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                      ),
                      const SizedBox(height: 8),
                      // Snap accent ring so DPAD focus on the switch row is
                      // visible on TV.
                      _FocusRing(
                        borderRadius: 12,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enabled'),
                          value: _enabled,
                          onChanged: (value) =>
                              setState(() => _enabled = value),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  _FocusRing(
                    borderRadius: 12,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  _FocusRing(
                    borderRadius: 12,
                    child: FilledButton(
                      onPressed: _save,
                      child: Text(widget.config == null ? 'Add' : 'Save'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editor-dialog field decoration: the outlined, dense look the deleted
/// _TvFriendlyTextFormField clone applied to every field. TvTextField borrows
/// the focusedBorder for its TV focus ring.
InputDecoration _engineFieldDecoration(
  BuildContext context,
  InputDecoration decoration,
) {
  final theme = Theme.of(context);
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: theme.colorScheme.outline),
  );
  return decoration.copyWith(
    border: decoration.border ?? border,
    enabledBorder: decoration.enabledBorder ?? border,
    focusedBorder:
        decoration.focusedBorder ??
        border.copyWith(
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
    errorBorder:
        decoration.errorBorder ??
        border.copyWith(borderSide: BorderSide(color: theme.colorScheme.error)),
    focusedErrorBorder:
        decoration.focusedErrorBorder ??
        border.copyWith(
          borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
        ),
    isDense: decoration.isDense ?? true,
    contentPadding:
        decoration.contentPadding ??
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

/// Snap accent ring painted while the wrapped control (Switch etc.) holds
/// focus — the stock Material focus overlay is invisible on the dark
/// settings theme. The wrapper node itself never takes focus.
class _FocusRing extends StatefulWidget {
  // `color` defaults to the accent CONSTANT, not the token: a const
  // constructor default cannot read a BuildContext. Callers that want the
  // themed accent pass it explicitly.
  const _FocusRing({
    required this.child,
    required this.borderRadius,
    this.color = kSettingsAccent,
  });

  final Widget child;
  final double borderRadius;
  final Color color;

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      // hasFocus includes descendants, so this fires when the child control
      // receives DPAD focus.
      onFocusChange: (f) => setState(() => _focused = f),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: _focused ? widget.color : Colors.transparent,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
