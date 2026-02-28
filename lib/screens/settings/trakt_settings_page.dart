import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/deep_link_service.dart';
import '../../services/trakt/trakt_service.dart';

class TraktSettingsPage extends StatefulWidget {
  const TraktSettingsPage({super.key});

  @override
  State<TraktSettingsPage> createState() => _TraktSettingsPageState();
}

class _TraktSettingsPageState extends State<TraktSettingsPage>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _username;

  // Store previous callback so we can restore it on dispose
  void Function(String, String?)? _previousCallback;
  Timer? _resumeResetTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _registerDeepLinkCallback();
  }

  @override
  void dispose() {
    _resumeResetTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    DeepLinkService().onTraktAuthorizationReceived = _previousCallback;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isConnecting && !_isConnected) {
      // User returned from browser without completing auth — reset after a grace period
      _resumeResetTimer?.cancel();
      _resumeResetTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _isConnecting && !_isConnected) {
          setState(() => _isConnecting = false);
        }
      });
    }
  }

  void _registerDeepLinkCallback() {
    final deepLinkService = DeepLinkService();
    _previousCallback = deepLinkService.onTraktAuthorizationReceived;
    deepLinkService.onTraktAuthorizationReceived = _handleAuthCallback;
  }

  void _handleAuthCallback(String code, String? state) {
    _resumeResetTimer?.cancel();

    if (!_isConnecting) return; // Stale callback — not in an active login flow

    // Validate OAuth state to prevent CSRF
    if (!TraktService.instance.validateState(state)) {
      debugPrint('Trakt OAuth: state mismatch — ignoring callback');
      if (mounted) {
        setState(() => _isConnecting = false);
        _showSnackBar('Authorization failed: invalid state');
      }
      return;
    }

    _handleAuthCode(code);
  }

  Future<void> _handleAuthCode(String code) async {
    try {
      if (!mounted) return;

      setState(() => _isConnecting = true);

      final success = await TraktService.instance.exchangeCode(code);

      if (!mounted) return;

      if (success) {
        final username = await TraktService.instance.getUsername();
        setState(() {
          _isConnected = true;
          _isConnecting = false;
          _username = username;
        });
        _showSnackBar('Connected to Trakt as ${username ?? 'unknown'}', isError: false);
      } else {
        setState(() => _isConnecting = false);
        _showSnackBar('Failed to connect to Trakt');
      }
    } catch (e) {
      debugPrint('Trakt: Auth code exchange error: $e');
      if (mounted) {
        setState(() => _isConnecting = false);
        _showSnackBar('Connection error: $e');
      }
    }
  }

  Future<void> _loadSettings() async {
    final isAuth = await TraktService.instance.isAuthenticated();
    final username = await TraktService.instance.getUsername();

    if (!mounted) return;

    setState(() {
      _isConnected = isAuth;
      _username = username;
      _loading = false;
    });
  }

  Future<void> _login() async {
    setState(() => _isConnecting = true);

    try {
      await TraktService.instance.launchAuth();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConnecting = false);
      _showSnackBar('Failed to open Trakt login: $e');
    }
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
                    SizedBox(
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
                        label: Text(_isConnecting ? 'Waiting for authorization...' : 'Login with Trakt'),
                      ),
                    )
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
                    'Clicking "Login with Trakt" will open your browser where you can authorize Debrify. '
                    'After approval, you\'ll be redirected back to the app automatically.',
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
}
