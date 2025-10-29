import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/storage_service.dart';
import '../../services/torbox_account_service.dart';
import '../../widgets/torbox_account_status_widget.dart';
import '../../services/main_page_bridge.dart';

class TorboxSettingsPage extends StatefulWidget {
  const TorboxSettingsPage({super.key});

  @override
  State<TorboxSettingsPage> createState() => _TorboxSettingsPageState();
}

class _TorboxSettingsPageState extends State<TorboxSettingsPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  final FocusNode _apiKeyFocusNode = FocusNode();
  static const Map<ShortcutActivator, Intent> _dpadShortcuts =
      <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
    SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
  };

  String? _savedApiKey;
  bool _isEditing = false;
  bool _obscure = true;
  bool _loading = true;
  bool _saving = false;
  bool _checkCacheBeforeSearch = false;
  bool _integrationEnabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiKey = await StorageService.getTorboxApiKey();
    final cachePref = await StorageService.getTorboxCacheCheckEnabled();
    final integrationEnabled =
        await StorageService.getTorboxIntegrationEnabled();
    setState(() {
      _savedApiKey = apiKey;
      _checkCacheBeforeSearch = cachePref;
      _loading = false;
      _integrationEnabled = integrationEnabled;
    });

    if (integrationEnabled && apiKey != null && apiKey.isNotEmpty) {
      await TorboxAccountService.refreshUserInfo();
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiKeyFocusNode.dispose();
    super.dispose();
  }

  void _snack(String message, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: err ? Colors.red : null,
      ),
    );
  }

  Future<void> _saveKey() async {
    final txt = _apiKeyController.text.trim();
    if (txt.isEmpty) {
      _snack('Please enter a valid API key', err: true);
      return;
    }

    if (_saving) return;
    debugPrint(
      'TorboxSettingsPage: Attempting to save API key (length=${txt.length}).',
    );
    setState(() => _saving = true);

    final isValid = await TorboxAccountService.validateAndGetUserInfo(txt);
    if (!mounted) return;

    if (!isValid) {
      setState(() => _saving = false);
      debugPrint('TorboxSettingsPage: Validation failed for provided key.');
      _snack('Invalid API key. Please check and try again.', err: true);
      return;
    }

    setState(() {
      _savedApiKey = txt;
      _isEditing = false;
      _saving = false;
      _apiKeyController.clear();
    });
    debugPrint('TorboxSettingsPage: API key saved successfully.');
    _snack('Torbox connected successfully');
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _deleteKey() async {
    debugPrint('TorboxSettingsPage: Deleting stored API key.');
    await StorageService.deleteTorboxApiKey();
    TorboxAccountService.clearUserInfo();
    FocusScope.of(context).unfocus();
    setState(() {
      _savedApiKey = null;
      _isEditing = false;
    });
    _snack('Torbox API key removed');
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _updateCacheCheck(bool value) async {
    setState(() => _checkCacheBeforeSearch = value);
    await StorageService.setTorboxCacheCheckEnabled(value);
  }

  Future<void> _updateIntegrationEnabled(bool value) async {
    setState(() {
      _integrationEnabled = value;
      if (!value) {
        _isEditing = false;
      }
    });
    await StorageService.setTorboxIntegrationEnabled(value);
    MainPageBridge.notifyIntegrationChanged();
    if (!mounted) return;
    if (value && _savedApiKey != null && _savedApiKey!.isNotEmpty) {
      await TorboxAccountService.refreshUserInfo();
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final user = TorboxAccountService.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Torbox Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile.adaptive(
              value: _integrationEnabled,
              onChanged: (value) => _updateIntegrationEnabled(value),
              title: const Text('Enable Torbox'),
              subtitle: const Text(
                'Turn this off to hide Torbox options across the app.',
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            ),
          ),
          const SizedBox(height: 16),
          IgnorePointer(
            ignoring: !_integrationEnabled,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _integrationEnabled ? 1.0 : 0.5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.key,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'API Key',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const Spacer(),
                              if (_savedApiKey != null && !_isEditing)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.green
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 14,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Connected',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_isEditing) ...[
                            Shortcuts(
                              shortcuts: _dpadShortcuts,
                              child: Actions(
                                actions: <Type, Action<Intent>>{
                                  NextFocusIntent: CallbackAction<NextFocusIntent>(
                                    onInvoke: (intent) {
                                      FocusScope.of(context).nextFocus();
                                      return null;
                                    },
                                  ),
                                  PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
                                    onInvoke: (intent) {
                                      FocusScope.of(context).previousFocus();
                                      return null;
                                    },
                                  ),
                                },
                                child: TextField(
                                  focusNode: _apiKeyFocusNode,
                                  controller: _apiKeyController,
                                  obscureText: _obscure,
                                  enabled: !_saving,
                                  textInputAction: TextInputAction.done,
                                  decoration: InputDecoration(
                                    labelText: 'Torbox API Key',
                                    prefixIcon: const Icon(Icons.security),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscure = !_obscure,
                                      ),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onSubmitted: (_) => _saving ? null : _saveKey(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _saving ? null : _saveKey,
                                    child: _saving
                                        ? const SizedBox(
                                            height: 18,
                                            width: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Save'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _saving
                                        ? null
                                        : () => setState(() {
                                              _isEditing = false;
                                              _apiKeyController.clear();
                                            }),
                                    child: const Text('Cancel'),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            if (_savedApiKey != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey[300]!,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        '••••••••••••••••••••••••••••••••',
                                        style:
                                            TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                    Icon(
                                      Icons.visibility_off,
                                      color: Colors.grey[500],
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _isEditing = true;
                                      if (_savedApiKey != null &&
                                          _savedApiKey!.isNotEmpty) {
                                            _apiKeyController
                                              ..text = _savedApiKey!
                                              ..selection = TextSelection.collapsed(
                                                offset: _savedApiKey!.length,
                                              );
                                      } else {
                                        _apiKeyController.clear();
                                      }
                                    });
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (mounted) {
                                        _apiKeyFocusNode.requestFocus();
                                      }
                                    });
                                  },
                                      icon: const Icon(Icons.edit),
                                      label: const Text('Edit'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _deleteKey,
                                      icon: const Icon(Icons.delete),
                                      label: const Text('Delete'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              FilledButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _isEditing = true;
                                    _apiKeyController.clear();
                                  });
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (mounted) {
                                      _apiKeyFocusNode.requestFocus();
                                    }
                                  });
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('Add API Key'),
                              ),
                            ]
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile.adaptive(
                          value: _checkCacheBeforeSearch,
                          onChanged: _updateCacheCheck,
                          title: const Text(
                            'Check Torbox cache during searches',
                          ),
                          subtitle: const Text(
                            'Verify Torbox has a cached copy before enabling quick actions in torrent search results. Non-cached torrents keep the Torbox button disabled.',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Text(
                            'Requires a Torbox API key. Debrify issues a fast cache check after each search; if anything fails, Torbox buttons remain enabled so your search flow continues.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (user != null) ...[
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.account_circle,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Account Information',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TorboxAccountStatusWidget(user: user),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.help_outline,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'How to get your Torbox API key',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '1. Visit: torbox.app\n'
                            '2. Log in and open Account Settings\n'
                            '3. Locate the API section\n'
                            '4. Copy the API key and paste it above',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Colors.grey[600],
                                  height: 1.5,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
