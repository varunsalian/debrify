import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/storage_service.dart';
import '../../services/trakt/trakt_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
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
  }

  Future<void> _login() async {
    setState(() => _isConnecting = true);

    try {
      final result = await TraktService.instance.requestDeviceCode();
      if (!mounted) return;

      if (result == null) {
        setState(() => _isConnecting = false);
        _showSnackBar('Failed to get device code from Trakt');
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConnecting = false);
      _showSnackBar('Failed to start login: $e');
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: _pollInterval), (_) => _pollOnce());
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
        _resetDeviceCodeState();
      });
      _showSnackBar('Connected to Trakt as ${username ?? 'unknown'}', isError: false);
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
    _showSnackBar('Logged out from Trakt', isError: false);
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Trakt Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Trakt Integration',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect your Trakt account to sync watchlists and track what you watch.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
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
                        _isConnected ? Icons.check_circle : Icons.circle_outlined,
                        color: _isConnected ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isConnected ? 'Connected' : 'Not connected',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            if (_username != null)
                              Text(
                                _username!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
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
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout),
                        label: const Text('Logout'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
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
            Card(
              child: SwitchListTile(
                title: const Text('Sync Catalog Items'),
                subtitle: const Text(
                  'Scrobble playback to Trakt for all content played from addons, not just Trakt items',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                value: _syncCatalogItems,
                onChanged: (value) {
                  setState(() => _syncCatalogItems = value);
                  StorageService.setTraktSyncCatalogItems(value);
                },
                activeColor: const Color(0xFFED1C24),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Colors.blue.shade300),
                      const SizedBox(width: 8),
                      const Text(
                        'How it works',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Clicking "Login with Trakt" will show a code on screen. '
                    'Enter this code at trakt.tv/activate on your phone or computer to authorize Debrify.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
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
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _isConnecting ? null : _login,
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
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const Text(
                'Enter this code:',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _userCode!));
                  _showSnackBar('Code copied to clipboard', isError: false);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText(
                      _userCode!,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy, size: 20, color: Colors.grey),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Verification URL
        GestureDetector(
          onTap: () {
            final url = _verificationUrl ?? 'https://trakt.tv/activate';
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          },
          child: Text(
            'Go to ${_verificationUrl ?? 'https://trakt.tv/activate'}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'on your phone or computer',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 12),

        // Countdown
        Text(
          'Code expires in ${_formatCountdown()}',
          style: const TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 16),

        // Cancel button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _stopDeviceCodeFlow,
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}
