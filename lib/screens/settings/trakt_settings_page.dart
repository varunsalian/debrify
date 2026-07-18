import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/trakt/trakt_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';

class TraktSettingsPage extends StatefulWidget {
  const TraktSettingsPage({super.key});

  @override
  State<TraktSettingsPage> createState() => _TraktSettingsPageState();
}

class _TraktSettingsPageState extends State<TraktSettingsPage> {
  bool _loading = true;
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _username;
  bool _syncCatalogItems = false;

  // Device code flow
  String? _userCode;
  String? _verificationUrl;
  String? _deviceCode;
  Timer? _pollTimer;
  int _pollInterval = 5;
  DateTime? _codeExpiresAt;
  Timer? _countdownTimer;

  // DPAD focus anchors: the login/logout button (whichever is shown) and the
  // Cancel button of the device-code card. Focus is handed between them as
  // the card appears/disappears so TV users are never stranded on nothing.
  final FocusNode _primaryButtonFocus = FocusNode(debugLabel: 'trakt-primary');
  final FocusNode _cancelFocus = FocusNode(debugLabel: 'trakt-cancel');

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('trakt_settings');
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
    if (!PlatformUtil.isAndroidTvCached) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.context != null) node.requestFocus();
    });
  }

  Future<void> _loadSettings() async {
    final isAuth = await TraktService.instance.isAuthenticated();
    final username = await TraktService.instance.getUsername();
    final syncCatalog = await StorageService.getTraktSyncCatalogItems();

    if (!mounted) return;

    setState(() {
      _isConnected = isAuth;
      _username = username;
      _syncCatalogItems = syncCatalog;
      _loading = false;
    });
    // TV entry focus: land DPAD users on the login/logout button — unless
    // the user already focused something (e.g. the AppBar back button)
    // while the async load ran. Reseeds elsewhere skip this guard on
    // purpose: there the focused node just unmounted.
    if (PlatformUtil.isAndroidTvCached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        if (_primaryButtonFocus.context != null) {
          _primaryButtonFocus.requestFocus();
        }
      });
    }
  }

  Future<void> _login() async {
    setState(() => _isConnecting = true);

    try {
      final result = await TraktService.instance.requestDeviceCode();
      if (!mounted) return;

      if (result == null) {
        setState(() => _isConnecting = false);
        _showSnackBar('Failed to get device code from Trakt');
        // Re-anchor DPAD focus on the (re-enabled) login button.
        _focusOnTv(_primaryButtonFocus);
        return;
      }

      final expiresIn = result['expires_in'] as int? ?? 600;
      _pollInterval = result['interval'] as int? ?? 5;

      setState(() {
        _userCode = result['user_code'] as String?;
        _verificationUrl = result['verification_url'] as String?;
        _deviceCode = result['device_code'] as String?;
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
    if (_deviceCode == null) return;

    final error = await TraktService.instance.pollDeviceToken(_deviceCode!);

    if (!mounted) return;

    if (error == null) {
      // Success
      _pollTimer?.cancel();
      _countdownTimer?.cancel();
      final username = await TraktService.instance.getUsername();
      if (!mounted) return;
      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _username = username;
        _syncCatalogItems = true;
        _resetDeviceCodeState();
      });
      await StorageService.setTraktSyncCatalogItems(true);
      AnalyticsService.integrationConnected('trakt', {
        'surface': 'settings',
        'method': 'device_code',
      });
      MainPageBridge.notifyIntegrationChanged();
      // Device-code card (and its Cancel) just left the tree — refocus.
      _focusOnTv(_primaryButtonFocus);
      _showSnackBar(
        'Connected to Trakt as ${username ?? 'unknown'}',
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
      case 'expired_token':
        _stopDeviceCodeFlow();
        _showSnackBar('Code expired. Please try again.');
        break;
      case 'access_denied':
        _stopDeviceCodeFlow();
        _showSnackBar('Authorization denied.');
        break;
      default:
        _stopDeviceCodeFlow();
        _showSnackBar('Authorization failed. Please try again.');
    }
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {}); // Refresh countdown display
      if (_codeExpiresAt != null && DateTime.now().isAfter(_codeExpiresAt!)) {
        _stopDeviceCodeFlow();
        _showSnackBar('Code expired. Please try again.');
      }
    });
  }

  void _stopDeviceCodeFlow() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    if (mounted) {
      setState(() {
        _isConnecting = false;
        _resetDeviceCodeState();
      });
      // The device-code card (and its Cancel button) just left the tree.
      _focusOnTv(_primaryButtonFocus);
    }
  }

  void _resetDeviceCodeState() {
    _userCode = null;
    _verificationUrl = null;
    _deviceCode = null;
    _codeExpiresAt = null;
  }

  Future<void> _logout() async {
    await TraktService.instance.logout();

    if (!mounted) return;

    setState(() {
      _isConnected = false;
      _username = null;
    });
    MainPageBridge.notifyIntegrationChanged();
    _showSnackBar('Logged out from Trakt', isError: false);
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? kSettingsRed : kSettingsGreen,
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
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Trakt Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Trakt Settings',
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
                    title: 'Trakt Integration',
                    subtitle:
                        'Connect your Trakt account to sync watchlists and track what you watch.',
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
                                color: _isConnected
                                    ? kSettingsGreen
                                    : kSettingsDim2,
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
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (_username != null)
                                      Text(
                                        _username!,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: kSettingsDim,
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
                            _FocusRing(
                              child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  focusNode: _primaryButtonFocus,
                                  onPressed: _logout,
                                  icon: const Icon(Icons.logout),
                                  label: const Text('Logout'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: kSettingsRed,
                                    side: BorderSide(
                                      color: kSettingsRed.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Sync Catalog Items toggle (only when connected)
                  if (_isConnected) ...[
                    const SizedBox(height: 16),
                    // _FocusRing: SwitchListTile's built-in focus highlight is
                    // too subtle for TV, so paint the accent ring around it.
                    _FocusRing(
                      child: Card(
                        child: SwitchListTile(
                          title: const Text('Sync Catalog Items'),
                          subtitle: Text(
                            'Scrobble playback to Trakt for all content played from addons, not just Trakt items',
                            style: TextStyle(fontSize: 12, color: kSettingsDim),
                          ),
                          value: _syncCatalogItems,
                          onChanged: (value) {
                            setState(() => _syncCatalogItems = value);
                            StorageService.setTraktSyncCatalogItems(value);
                          },
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Info banner
                  const SettingsInfoBanner(
                    text:
                        'How it works: clicking "Login with Trakt" will show a code on screen. '
                        'Enter this code at trakt.tv/activate on your phone or computer to authorize Debrify.',
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
    // Show device code UI when connecting
    if (_isConnecting && _userCode != null) {
      return _buildDeviceCodeCard();
    }

    // Login button
    return _FocusRing(
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          focusNode: _primaryButtonFocus,
          // Busy no-op instead of disabling: a disabled button can't hold
          // DPAD focus, which would strand TV users mid-login.
          onPressed: _isConnecting ? () {} : _login,
          icon: _isConnecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.login),
          label: Text(_isConnecting ? 'Getting code...' : 'Login with Trakt'),
        ),
      ),
    );
  }

  Widget _buildDeviceCodeCard() {
    return Column(
      children: [
        // User code display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: kSettingsPanel2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kSettingsLine),
          ),
          child: Column(
            children: [
              Text(
                'Enter this code:',
                style: TextStyle(fontSize: 14, color: kSettingsDim),
              ),
              const SizedBox(height: 8),
              // InkWell (not GestureDetector) so the copy action is DPAD
              // focusable; plain Text (not SelectableText) so arrow keys
              // traverse instead of moving a text cursor.
              _FocusRing(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
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
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                            fontFamily: 'monospace',
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.copy, size: 20, color: kSettingsDim),
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
        _FocusRing(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              final url = _verificationUrl ?? 'https://trakt.tv/activate';
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                'Go to ${_verificationUrl ?? 'https://trakt.tv/activate'}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: kSettingsAccent2,
                  decoration: TextDecoration.underline,
                  decorationColor: kSettingsAccent2,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'on your phone or computer',
          style: TextStyle(fontSize: 13, color: kSettingsDim),
        ),
        const SizedBox(height: 12),

        // Countdown
        Text(
          'Code expires in ${_formatCountdown()}',
          style: TextStyle(fontSize: 13, color: kSettingsDim),
        ),
        const SizedBox(height: 16),

        // Cancel button
        _FocusRing(
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              focusNode: _cancelFocus,
              onPressed: _stopDeviceCodeFlow,
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
class _FocusRing extends StatefulWidget {
  final Widget child;
  const _FocusRing({required this.child});

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      // hasFocus includes descendants, so this fires when the wrapped
      // control receives DPAD focus.
      onFocusChange: (f) => setState(() => _focused = f),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: _focused ? kSettingsAccent : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: widget.child,
      ),
    );
  }
}
