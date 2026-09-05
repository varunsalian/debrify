import 'widgets/settings_load_error.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/simkl/simkl_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

class SimklSettingsPage extends StatefulWidget {
  const SimklSettingsPage({super.key});

  @override
  State<SimklSettingsPage> createState() => _SimklSettingsPageState();
}

class _SimklSettingsPageState extends State<SimklSettingsPage> {
  bool _loading = true;
  bool _loadFailed = false;
  int _loadGeneration = 0;
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _username;

  // PIN flow
  String? _userCode;
  String? _verificationUrl;
  Timer? _pollTimer;
  int _pollInterval = 5;
  DateTime? _codeExpiresAt;
  Timer? _countdownTimer;

  // DPAD focus anchors: the login/logout button (whichever is shown) and the
  // Cancel button of the PIN card. Focus is handed between them as the card
  // appears/disappears so TV users are never stranded on nothing.
  final FocusNode _primaryButtonFocus = FocusNode(debugLabel: 'simkl-primary');
  final FocusNode _cancelFocus = FocusNode(debugLabel: 'simkl-cancel');

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('simkl_settings');
    _loadSettings();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _primaryButtonFocus.dispose();
    _cancelFocus.dispose();
    super.dispose();
  }

  void _focusOnTv(FocusNode node) {
    if (!PlatformUtil.isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.context != null) node.requestFocus();
    });
  }

  Future<void> _loadSettings() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final (isAuth, username) = await (() async => (
        await SimklService.instance.isAuthenticated(),
        await SimklService.instance.getUsername(),
      ))().timeout(const Duration(seconds: 5));

      if (!mounted || generation != _loadGeneration) return;

      setState(() {
        _isConnected = isAuth;
        _username = username;
        _loading = false;
      });
      // TV entry focus: land DPAD users on the login/logout button — unless
      // the user already focused something (e.g. the AppBar back button)
      // while the async load ran. Reseeds elsewhere skip this guard on
      // purpose: there the focused node just unmounted.
      if (PlatformUtil.isTelevision) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _loadGeneration) return;
          final primary = FocusManager.instance.primaryFocus;
          if (primary != null && primary is! FocusScopeNode) return;
          if (_primaryButtonFocus.context != null) {
            _primaryButtonFocus.requestFocus();
          }
        });
      }
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _login() async {
    setState(() => _isConnecting = true);

    try {
      final result = await SimklService.instance.requestPin();
      if (!mounted) return;

      if (result == null) {
        setState(() => _isConnecting = false);
        _showSnackBar('Failed to get a code from Simkl');
        // Re-anchor DPAD focus on the (re-enabled) login button.
        _focusOnTv(_primaryButtonFocus);
        return;
      }

      final expiresIn = result['expires_in'] as int? ?? 900;
      _pollInterval = result['interval'] as int? ?? 5;

      setState(() {
        _userCode = result['user_code'] as String?;
        _verificationUrl = result['verification_url'] as String?;
        _codeExpiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      });

      _startCountdownTimer();
      _startPolling();
      // The login button just disappeared under focus — move to Cancel.
      _focusOnTv(_cancelFocus);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConnecting = false);
      _showSnackBar('Failed to start login: $e');
      // Re-anchor DPAD focus on the (re-enabled) login button.
      _focusOnTv(_primaryButtonFocus);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: _pollInterval),
      (_) => _pollOnce(),
    );
  }

  Future<void> _pollOnce() async {
    if (_userCode == null) return;

    final error = await SimklService.instance.pollPin(_userCode!);

    if (!mounted) return;

    if (error == null) {
      // Success
      _pollTimer?.cancel();
      _countdownTimer?.cancel();
      final username = await SimklService.instance.getUsername();
      if (!mounted) return;
      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _username = username;
        _resetPinState();
      });
      AnalyticsService.integrationConnected('simkl', {
        'surface': 'settings',
        'method': 'pin',
      });
      MainPageBridge.notifyIntegrationChanged();
      // PIN card (and its Cancel) just left the tree — refocus.
      _focusOnTv(_primaryButtonFocus);
      _showSnackBar(
        'Connected to Simkl as ${username ?? 'unknown'}',
        isError: false,
      );
      return;
    }

    switch (error) {
      case 'authorization_pending':
      case 'network_error':
        // Transient — keep polling, the timer will fire again
        break;
      case 'slow_down':
        _pollInterval += 5;
        _pollTimer?.cancel();
        _startPolling();
        break;
      default:
        _stopPinFlow();
        _showSnackBar('Authorization failed. Please try again.');
    }
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {}); // Refresh countdown display
      if (_codeExpiresAt != null && DateTime.now().isAfter(_codeExpiresAt!)) {
        _stopPinFlow();
        _showSnackBar('Code expired. Please try again.');
      }
    });
  }

  void _stopPinFlow() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    if (mounted) {
      setState(() {
        _isConnecting = false;
        _resetPinState();
      });
      // The PIN card (and its Cancel button) just left the tree.
      _focusOnTv(_primaryButtonFocus);
    }
  }

  void _resetPinState() {
    _userCode = null;
    _verificationUrl = null;
    _codeExpiresAt = null;
  }

  Future<void> _logout() async {
    try {
      await SimklService.instance.logout();
    } catch (_) {
      _showSnackBar(
        'This connection is shared. Revoke or transfer profile access before disconnecting.',
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _isConnected = false;
      _username = null;
    });
    MainPageBridge.notifyIntegrationChanged();
    final fellBack = await StorageService.takeTrackingProgressFallbackNotice();
    if (!mounted) return;
    _showSnackBar(
      fellBack
          ? 'Logged out from Simkl. Progress source changed to Smart.'
          : 'Logged out from Simkl',
      isError: false,
    );
  }

  void _showSnackBar(String message, {bool isError = true}) {
    final t = AppThemeScope.of(context).settings;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? t.danger : t.success,
      ),
    );
  }

  String _formatCountdown() {
    if (_codeExpiresAt == null) return '';
    final remaining = _codeExpiresAt!.difference(DateTime.now());
    if (remaining.isNegative) return 'Expired';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Simkl Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadFailed) {
      return SettingsPageScaffold(
        title: 'Simkl Settings',
        body: SettingsLoadError(onRetry: _loadSettings),
      );
    }

    return SettingsPageScaffold(
      title: 'Simkl Settings',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SettingsPageHeader(
                    icon: Icons.sync_rounded,
                    title: 'Simkl Integration',
                    subtitle:
                        'Connect your Simkl account to sync watchlists and track what you watch.',
                  ),
                  const SizedBox(height: 24),

                  // Connection status card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isConnected
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: _isConnected ? t.success : t.dim2,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isConnected
                                          ? 'Connected'
                                          : 'Not connected',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                        color: app.core.tx,
                                      ),
                                    ),
                                    if (_username != null)
                                      Text(
                                        _username!,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: t.dim,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (!_isConnected)
                            _buildLoginSection()
                          else
                            _SimklFocusRing(
                              child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  focusNode: _primaryButtonFocus,
                                  onPressed: _logout,
                                  icon: const Icon(Icons.logout),
                                  label: const Text('Logout'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: t.danger,
                                    side: BorderSide(
                                      color: t.danger.withValues(alpha: 0.4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Info banner
                  const SettingsInfoBanner(
                    text:
                        'How it works: clicking "Login with Simkl" will show a code on screen. '
                        'Enter this code at simkl.com/pin on your phone or computer to authorize Debrify.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginSection() {
    final app = AppThemeScope.of(context);
    // Show PIN UI when connecting
    if (_isConnecting && _userCode != null) {
      return _buildPinCard();
    }

    // Login button
    return _SimklFocusRing(
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          focusNode: _primaryButtonFocus,
          // Busy no-op instead of disabling: a disabled button can't hold
          // DPAD focus, which would strand TV users mid-login.
          onPressed: _isConnecting ? () {} : _login,
          icon: _isConnecting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: app.core.tx,
                  ),
                )
              : const Icon(Icons.login),
          label: Text(_isConnecting ? 'Getting code...' : 'Login with Simkl'),
        ),
      ),
    );
  }

  Widget _buildPinCard() {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Column(
      children: [
        // User code display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: t.panel2,
            borderRadius: app.shape.br(12),
            border: Border.all(color: t.line),
          ),
          child: Column(
            children: [
              Text(
                'Enter this code:',
                style: TextStyle(fontSize: 14, color: t.dim),
              ),
              const SizedBox(height: 8),
              // InkWell (not GestureDetector) so the copy action is DPAD
              // focusable; plain Text (not SelectableText) so arrow keys
              // traverse instead of moving a text cursor.
              _SimklFocusRing(
                child: InkWell(
                  borderRadius: app.shape.br(8),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _userCode!));
                    _showSnackBar('Code copied to clipboard', isError: false);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _userCode!,
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                            fontFamily: 'monospace',
                            color: app.core.tx,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.copy, size: 20, color: t.dim),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Verification URL (focusable link)
        _SimklFocusRing(
          child: InkWell(
            borderRadius: app.shape.br(8),
            onTap: () {
              final url = _verificationUrl ?? 'https://simkl.com/pin';
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                'Go to ${_verificationUrl ?? 'https://simkl.com/pin'}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: t.accent2,
                  decoration: TextDecoration.underline,
                  decorationColor: t.accent2,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'on your phone or computer',
          style: TextStyle(fontSize: 13, color: t.dim),
        ),
        const SizedBox(height: 12),

        // Countdown
        Text(
          'Code expires in ${_formatCountdown()}',
          style: TextStyle(fontSize: 13, color: t.dim),
        ),
        const SizedBox(height: 16),

        // Cancel button
        _SimklFocusRing(
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              focusNode: _cancelFocus,
              onPressed: _stopPinFlow,
              child: const Text('Cancel'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Paints a snap accent ring around [child] while any descendant holds DPAD
/// focus — Material's own focus overlay is too subtle for TV. Non-focusable
/// itself, so it adds no traversal stop. Snap, don't tween (TV GPU rule).
///
/// Duplicated from `trakt_settings_page.dart`'s private `_FocusRing` rather
/// than shared, so this file never has to touch the Trakt one.
class _SimklFocusRing extends StatefulWidget {
  final Widget child;
  const _SimklFocusRing({required this.child});

  @override
  State<_SimklFocusRing> createState() => _SimklFocusRingState();
}

class _SimklFocusRingState extends State<_SimklFocusRing> {
  /// Live, never cached: Flutter does not guarantee the falling edge of
  /// `onFocusChange` — popping a route opened with OK restores focus to the
  /// modal scope rather than to a row, so rows that were focus-walked on the
  /// way in are never told they lost it and keep painting as focused. See the
  /// note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode => _ownFocusNode ??= FocusNode();
  bool get _focused => _focusNode.hasFocus;

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      // hasFocus includes descendants, so this fires when the wrapped
      // control receives DPAD focus.
      focusNode: _focusNode,
      onFocusChange: (_) => setState(() {}),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: _focused ? t.accent : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: widget.child,
      ),
    );
  }
}
