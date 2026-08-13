import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import '../../widgets/tv_text_field.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// Settings page for the MDBList integration.
///
/// MDBList authenticates with a single API key (from mdblist.com/preferences),
/// so this page is an API-key entry screen — mirroring the debrid-provider
/// pages — rather than a device-code flow like Trakt. Connecting validates the
/// key against the API and, on success, shows a small account summary. List
/// browsing is wired up in a later step.
class MdblistSettingsPage extends StatefulWidget {
  const MdblistSettingsPage({super.key});

  @override
  State<MdblistSettingsPage> createState() => _MdblistSettingsPageState();
}

class _MdblistSettingsPageState extends State<MdblistSettingsPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  final FocusNode _apiKeyFocusNode = FocusNode();
  final FocusNode _addApiKeyButtonFocusNode = FocusNode();
  final FocusNode _saveButtonFocusNode = FocusNode();
  final FocusNode _logoutButtonFocusNode = FocusNode();

  String? _savedApiKey;
  MdblistAccount? _account;
  bool _isEditing = false;
  bool _obscure = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('mdblist_settings');
    _load();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiKeyFocusNode.dispose();
    _addApiKeyButtonFocusNode.dispose();
    _saveButtonFocusNode.dispose();
    _logoutButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final configured = await StorageService.hasMdblistCredential();
    if (!mounted) return;
    setState(() {
      _savedApiKey = configured ? '' : null;
      _account = MdblistService.instance.currentAccount;
      _loading = false;
    });

    // Refresh the account card in the background if we're connected. A failure
    // here is non-fatal — the stored key stays put (it may just be offline).
    if (configured) {
      final account = await MdblistService.instance.refreshAccount();
      if (mounted && account != null) {
        setState(() => _account = account);
      }
    }
  }

  // Save/Cancel/logout swap out the block the DPAD focus was on. Re-seed focus
  // once the new subtree is mounted. TV-only: touch users don't rely on focus.
  void _refocusOnTv(FocusNode node) {
    if (!PlatformUtil.isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  // Entry-focus seed: right after a route push primary focus rests on the
  // route's FocusScopeNode, so a non-scope node means the user already moved
  // somewhere (e.g. the back button) while this page loaded — don't steal it.
  bool get _seedEntryFocus {
    if (!PlatformUtil.isTelevision) return false;
    final primary = FocusManager.instance.primaryFocus;
    return primary == null || primary is FocusScopeNode;
  }

  void _snack(String message, {bool err = false}) {
    final t = AppThemeScope.of(context).settings;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: err ? t.danger : null),
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

    final account = await MdblistService.instance.connect(txt);
    if (!mounted) return;

    if (account == null) {
      setState(() => _saving = false);
      // _saving briefly disabled (and defocused) the Save button; put DPAD
      // focus back on it — not the TextField, which pops the soft keyboard.
      _refocusOnTv(_saveButtonFocusNode);
      _snack('Invalid API key. Please check and try again.', err: true);
      return;
    }

    setState(() {
      _savedApiKey = '';
      _account = account;
      _isEditing = false;
      _saving = false;
      _apiKeyController.clear();
    });
    _refocusOnTv(_logoutButtonFocusNode);
    AnalyticsService.integrationConnected('mdblist', {'surface': 'settings'});
    _snack('MDBList connected successfully');
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _deleteKey() async {
    try {
      await MdblistService.instance.logout();
    } catch (_) {
      _snack(
        'This connection is shared. Revoke or transfer profile access before disconnecting.',
        err: true,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _savedApiKey = null;
      _account = null;
      _isEditing = false;
      _apiKeyController.clear();
    });
    _snack('Logged out from MDBList');
    MainPageBridge.notifyIntegrationChanged();
    _refocusOnTv(_addApiKeyButtonFocusNode);
  }

  Future<void> _openApiKeyPage() async {
    final uri = Uri.parse('https://mdblist.com/preferences/');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'MDBList Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'MDBList Settings',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SettingsPageHeader(
                  icon: Icons.playlist_add_check_circle_outlined,
                  title: 'MDBList Integration',
                  subtitle:
                      'Connect your MDBList account to browse your lists inside '
                      'Discover and Stremio TV.',
                ),
                const SizedBox(height: 24),
                _buildApiKeyCard(context),
                if (_account != null) ...[
                  const SizedBox(height: 16),
                  _buildAccountCard(context),
                ],
                const SizedBox(height: 16),
                _buildHelpCard(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildApiKeyCard(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.key, color: t.accent2, size: 20),
                const SizedBox(width: 8),
                Text(
                  'API Key',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_savedApiKey != null && !_isEditing) _connectedBadge(),
              ],
            ),
            const SizedBox(height: 16),
            if (_isEditing)
              _buildEditor()
            else if (_savedApiKey != null)
              _buildConnectedActions()
            else
              _buildAddKeyButton(),
          ],
        ),
      ),
    );
  }

  Widget _connectedBadge() {
    final t = AppThemeScope.of(context).settings;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: t.success, size: 14),
          const SizedBox(width: 4),
          Text('Connected', style: TextStyle(color: t.success, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    final t = AppThemeScope.of(context).settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TvTextField(
          focusNode: _apiKeyFocusNode,
          controller: _apiKeyController,
          obscureText: _obscure,
          enabled: !_saving,
          textInputAction: TextInputAction.done,
          onDownArrow: () => FocusScope.of(context).nextFocus(),
          onUpArrow: () => FocusScope.of(context).previousFocus(),
          decoration: InputDecoration(
            labelText: 'MDBList API Key',
            prefixIcon: const Icon(Icons.security),
            suffixIcon: IconButton(
              focusColor: t.accent.withValues(alpha: 0.4),
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onSubmitted: (_) => _saving ? null : _saveKey(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _FocusRing(
                radius: 12,
                child: FilledButton(
                  focusNode: _saveButtonFocusNode,
                  onPressed: _saving ? null : _saveKey,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FocusRing(
                radius: 12,
                child: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () {
                          setState(() {
                            _isEditing = false;
                            _apiKeyController.clear();
                          });
                          _refocusOnTv(
                            _savedApiKey != null
                                ? _logoutButtonFocusNode
                                : _addApiKeyButtonFocusNode,
                          );
                        },
                  child: const Text('Cancel'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConnectedActions() {
    final t = AppThemeScope.of(context).settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.panel2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '••••••••••••••••••••••••••••••••',
                  style: TextStyle(color: t.dim),
                ),
              ),
              Icon(Icons.visibility_off, color: t.dim2, size: 16),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _FocusRing(
          radius: 12,
          child: OutlinedButton.icon(
            focusNode: _logoutButtonFocusNode,
            onPressed: _deleteKey,
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            style: OutlinedButton.styleFrom(
              foregroundColor: t.danger,
              side: BorderSide(color: t.danger.withValues(alpha: 0.45)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddKeyButton() {
    return _FocusRing(
      radius: 12,
      child: FilledButton.icon(
        focusNode: _addApiKeyButtonFocusNode,
        autofocus: _seedEntryFocus,
        onPressed: () {
          setState(() {
            _isEditing = true;
            _apiKeyController.clear();
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _apiKeyFocusNode.requestFocus();
          });
        },
        icon: const Icon(Icons.add),
        label: const Text('Add API Key'),
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    final account = _account!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_circle, color: t.accent2, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Account',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (account.username != null)
              _accountRow('Username', account.username!),
            _accountRow(
              'Your lists',
              account.listCount == 1 ? '1 list' : '${account.listCount} lists',
            ),
            if (account.patronStatus != null &&
                account.patronStatus!.isNotEmpty)
              _accountRow('Supporter', _prettyPatron(account.patronStatus!)),
            if (account.apiRequests > 0)
              _accountRow(
                'API usage',
                '${account.apiRequestsUsed} / ${account.apiRequests} today',
              ),
          ],
        ),
      ),
    );
  }

  Widget _accountRow(String label, String value) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(color: t.dim)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w500, color: app.core.tx),
            ),
          ),
        ],
      ),
    );
  }

  String _prettyPatron(String raw) {
    switch (raw) {
      case 'active_patron':
        return 'Active';
      case 'former_patron':
        return 'Former';
      case 'declined_patron':
        return 'Declined';
      default:
        return raw.replaceAll('_', ' ');
    }
  }

  Widget _buildHelpCard(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, color: t.accent2, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'How to get your MDBList API key',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '1. Visit mdblist.com/preferences\n'
              '2. Log in if prompted\n'
              '3. Find the "API Access" section and copy your key\n'
              '4. Paste it above and tap Save',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: t.dim, height: 1.5),
            ),
            const SizedBox(height: 12),
            _FocusRing(
              radius: 12,
              child: OutlinedButton.icon(
                onPressed: _openApiKeyPage,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open mdblist.com/preferences'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the house focus ring (accent border, matching the other settings
/// pages) around a child whose inner control owns DPAD focus. Snap decoration
/// — no tween — per the TV GPU rule. skipTraversal keeps the wrapper itself
/// out of the focus order.
class _FocusRing extends StatefulWidget {
  final Widget child;
  final double radius;

  const _FocusRing({required this.child, this.radius = 14});

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      onFocusChange: (f) => setState(() => _focused = f),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: _focused ? t.accent : Colors.transparent,
            width: 1,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
