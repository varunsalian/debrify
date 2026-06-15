import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/storage_service.dart';
import '../../services/premiumize_account_service.dart';
import '../../services/aptabase_service.dart';
import '../../widgets/premiumize_account_status_widget.dart';
import '../../services/main_page_bridge.dart';

class PremiumizeSettingsPage extends StatefulWidget {
  const PremiumizeSettingsPage({super.key});

  @override
  State<PremiumizeSettingsPage> createState() => _PremiumizeSettingsPageState();
}

class _PremiumizeSettingsPageState extends State<PremiumizeSettingsPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  final FocusNode _apiKeyFocusNode = FocusNode();
  final FocusNode _addApiKeyButtonFocusNode = FocusNode();
  final FocusNode _logoutButtonFocusNode = FocusNode();
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
  bool _integrationEnabled = true;
  bool _checkCacheBeforeSearch = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiKey = await StorageService.getPremiumizeApiKey();
    final integrationEnabled =
        await StorageService.getPremiumizeIntegrationEnabled();
    final cachePref = await StorageService.getPremiumizeCacheCheckEnabled();
    setState(() {
      _savedApiKey = apiKey;
      _integrationEnabled = integrationEnabled;
      _checkCacheBeforeSearch = cachePref;
      _loading = false;
    });

    if (integrationEnabled && apiKey != null && apiKey.isNotEmpty) {
      await PremiumizeAccountService.refreshUserInfo();
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiKeyFocusNode.dispose();
    _addApiKeyButtonFocusNode.dispose();
    _logoutButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _updateCacheCheck(bool value) async {
    setState(() => _checkCacheBeforeSearch = value);
    await StorageService.setPremiumizeCacheCheckEnabled(value);
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
    setState(() => _saving = true);

    final isValid = await PremiumizeAccountService.validateAndGetUserInfo(txt);
    if (!mounted) return;

    if (!isValid) {
      setState(() => _saving = false);
      _snack('Invalid API key. Please check and try again.', err: true);
      return;
    }

    setState(() {
      _savedApiKey = txt;
      _isEditing = false;
      _saving = false;
      _apiKeyController.clear();
    });
    AptabaseService.trackInBackground('provider_connected', {
      'provider': 'premiumize',
      'surface': 'settings',
    });
    _snack('Premiumize connected successfully');
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _deleteKey() async {
    await StorageService.deletePremiumizeApiKey();
    PremiumizeAccountService.clearUserInfo();
    _snack('Logged out successfully', err: false);
    MainPageBridge.notifyIntegrationChanged();
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _updateIntegrationEnabled(bool value) async {
    setState(() {
      _integrationEnabled = value;
      if (!value) {
        _isEditing = false;
      }
    });
    await StorageService.setPremiumizeIntegrationEnabled(value);
    MainPageBridge.notifyIntegrationChanged();
    if (!mounted) return;
    if (value && _savedApiKey != null && _savedApiKey!.isNotEmpty) {
      await PremiumizeAccountService.refreshUserInfo();
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final user = PremiumizeAccountService.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Premiumize Settings')),
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
              title: const Text('Enable Premiumize'),
              subtitle: const Text(
                'Turn this off to hide Premiumize options across the app.',
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 4,
              ),
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
                                color: Theme.of(context).colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'API Key',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              if (_savedApiKey != null && !_isEditing)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.green.withValues(
                                        alpha: 0.3,
                                      ),
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
                                  NextFocusIntent:
                                      CallbackAction<NextFocusIntent>(
                                        onInvoke: (intent) {
                                          FocusScope.of(context).nextFocus();
                                          return null;
                                        },
                                      ),
                                  PreviousFocusIntent:
                                      CallbackAction<PreviousFocusIntent>(
                                        onInvoke: (intent) {
                                          FocusScope.of(
                                            context,
                                          ).previousFocus();
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
                                    labelText: 'Premiumize API Key',
                                    prefixIcon: const Icon(Icons.security),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                      ),
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onSubmitted: (_) =>
                                      _saving ? null : _saveKey(),
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
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        '••••••••••••••••••••••••••••••••',
                                        style: TextStyle(color: Colors.grey),
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
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  focusNode: _logoutButtonFocusNode,
                                  onPressed: _deleteKey,
                                  icon: const Icon(Icons.logout),
                                  label: const Text('Logout'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                ),
                              ),
                            ] else ...[
                              FilledButton.icon(
                                focusNode: _addApiKeyButtonFocusNode,
                                onPressed: () {
                                  setState(() {
                                    _isEditing = true;
                                    _apiKeyController.clear();
                                  });
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) {
                                      _apiKeyFocusNode.requestFocus();
                                    }
                                  });
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('Add API Key'),
                              ),
                            ],
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
                            'Check Premiumize cache during searches',
                          ),
                          subtitle: const Text(
                            'Show a "PM" badge on torrent search results that are '
                            'already cached on Premiumize, so you know which ones '
                            'play instantly.',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Text(
                            'Cache checks are free (no fair-use cost). If a check '
                            'fails, results stay usable.',
                            style: Theme.of(context).textTheme.bodySmall
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
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Account Information',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            PremiumizeAccountStatusWidget(user: user),
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
                                color: Theme.of(context).colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'How to get your Premiumize API key',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '1. Visit: premiumize.me/account\n'
                            '2. Log in if prompted\n'
                            '3. Find the "API" section\n'
                            '4. Copy your API key and paste it above',
                            style: Theme.of(context).textTheme.bodyMedium
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
