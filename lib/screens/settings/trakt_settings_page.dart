import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/storage_service.dart';
import '../../services/trakt_service.dart';
import '../../services/android_native_downloader.dart';
import 'dart:async';

class TraktSettingsPage extends StatefulWidget {
  const TraktSettingsPage({super.key});

  @override
  State<TraktSettingsPage> createState() => _TraktSettingsPageState();
}

class _TraktSettingsPageState extends State<TraktSettingsPage> {
  bool _isConnected = false;
  String? _username;
  bool _scrobblingEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final token = await StorageService.getTraktAccessToken();
    final username = await StorageService.getTraktUsername();
    final enabled = await StorageService.getTraktEnabled();

    if (!mounted) return;

    setState(() {
      _isConnected = token != null;
      _username = username;
      _scrobblingEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _connectToTrakt() async {
    final isTv = await AndroidNativeDownloader.isTelevision();
    
    if (isTv) {
      final codes = await TraktService.generateDeviceCode();
      if (codes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate pairing code')),
        );
        return;
      }
      
      if (!mounted) return;
      _showPairingDialog(codes);
    } else {
      final url = Uri.parse(TraktService.getAuthUrl());
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please complete the login in your browser'),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not launch browser'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPairingDialog(Map<String, dynamic> codes) {
    final String userCode = codes['user_code'];
    final String verificationUrl = codes['verification_url'];
    final String deviceCode = codes['device_code'];
    final int interval = codes['interval'];
    final int expiresIn = codes['expires_in'];

    Timer? pollTimer;
    Timer? expirationTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Start polling if not already started
          pollTimer ??= Timer.periodic(Duration(seconds: interval), (timer) async {
            final result = await TraktService.pollForDeviceToken(deviceCode);
            
            if (result['status'] == 'success') {
              timer.cancel();
              expirationTimer?.cancel();
              if (context.mounted) Navigator.of(context).pop(true);
            } else if (result['status'] == 'expired') {
              timer.cancel();
              expirationTimer?.cancel();
              if (context.mounted) Navigator.of(context).pop(false);
            }
          });

          // Set expiration timer if not already set
          expirationTimer ??= Timer(Duration(seconds: expiresIn), () {
            pollTimer?.cancel();
            if (context.mounted) Navigator.of(context).pop(false);
          });

          return AlertDialog(
            title: const Text('Connect to Trakt'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'On another device (phone or computer), go to:',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  verificationUrl,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'And enter this code:',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade900, width: 2),
                  ),
                  child: Text(
                    userCode,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text(
                  'Waiting for authorization...',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  pollTimer?.cancel();
                  Navigator.of(context).pop(false);
                },
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    ).then((success) {
      pollTimer?.cancel();
      expirationTimer?.cancel();

      if (!mounted) return;

      if (success == true) {
        _loadSettings();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully connected to Trakt!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });
  }


  Future<void> _toggleScrobbling(bool value) async {
    await StorageService.setTraktEnabled(value);
    setState(() {
      _scrobblingEnabled = value;
    });
  }

  Future<void> _logout() async {
    await TraktService.logout();
    await _loadSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Disconnected from Trakt'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trakt Scrobbling'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (!TraktService.hasCredentials)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade900),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
                            const SizedBox(width: 8),
                            const Text(
                              'Trakt Credentials Missing',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'This build of Debrify does not have Trakt API credentials. In your Trakt App settings, set the Redirect URI to:',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'debrify://trakt-auth',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Then rebuild the app with:',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'flutter run \\\n  --dart-define=TRAKT_CLIENT_ID=your_id \\\n  --dart-define=TRAKT_CLIENT_SECRET=your_secret',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _isConnected ? Colors.red.shade900 : theme.colorScheme.surfaceVariant,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.movie_filter,
                      size: 40,
                      color: _isConnected ? Colors.white : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    _isConnected ? 'Connected to Trakt' : 'Not Connected',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                if (_isConnected && _username != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Logged in as $_username',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 32),
                
                if (!_isConnected)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: FilledButton.icon(
                      onPressed: _connectToTrakt,
                      icon: const Icon(Icons.login),
                      label: const Text('Connect to Trakt'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade900,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                  )
                else ...[
                  SwitchListTile(
                    title: const Text('Enable Scrobbling'),
                    subtitle: const Text('Automatically track what you watch'),
                    value: _scrobblingEnabled,
                    onChanged: _toggleScrobbling,
                    secondary: const Icon(Icons.sync),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Sync Now'),
                    subtitle: const Text('Manually sync your history'),
                    leading: const Icon(Icons.refresh),
                    onTap: () {
                       // Optional: Add manual sync logic
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('Syncing with Trakt...')),
                       );
                    },
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Disconnect Account'),
                    subtitle: const Text('Remove Trakt integration'),
                    leading: const Icon(Icons.logout, color: Colors.red),
                    textColor: Colors.red,
                    onTap: _logout,
                  ),
                ],
                
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'Trakt scrobbling allows you to automatically keep track of movies and TV shows you watch, sync progress across devices, and get personalized recommendations.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
    );
  }
}
