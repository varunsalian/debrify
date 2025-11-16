import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/storage_service.dart';
import '../../services/pikpak_api_service.dart';
import '../../services/main_page_bridge.dart';

class PikPakSettingsPage extends StatefulWidget {
  const PikPakSettingsPage({super.key});

  @override
  State<PikPakSettingsPage> createState() => _PikPakSettingsPageState();
}

class _PikPakSettingsPageState extends State<PikPakSettingsPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _pikpakEnabled = false;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final enabled = await StorageService.getPikPakEnabled();
    final email = await StorageService.getPikPakEmail();
    final isAuth = await PikPakApiService.instance.isAuthenticated();

    if (!mounted) return;

    setState(() {
      _pikpakEnabled = enabled;
      _emailController.text = email ?? '';
      _isConnected = isAuth;
      _loading = false;
    });
  }

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackBar('Please fill in both email and password');
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      final success = await PikPakApiService.instance.login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      if (success) {
        setState(() {
          _isConnected = true;
        });
        await StorageService.setPikPakEnabled(true);
        _showSnackBar('Connected successfully!', isError: false);

        // Clear password field for security
        _passwordController.clear();
      } else {
        _showSnackBar('Login failed. Please check your credentials.');
      }
    } catch (e) {
      print('Error logging in: $e');
      if (!mounted) return;
      _showSnackBar('Login error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    try {
      await PikPakApiService.instance.logout();
      await StorageService.setPikPakEnabled(false);

      if (!mounted) return;

      setState(() {
        _isConnected = false;
        _passwordController.clear();
      });

      _showSnackBar('Logged out successfully', isError: false);
    } catch (e) {
      print('Error logging out: $e');
      if (!mounted) return;
      _showSnackBar('Logout error: $e');
    }
  }

  Future<void> _testConnection() async {
    try {
      _showSnackBar('Testing connection...', isError: false);

      final success = await PikPakApiService.instance.testConnection();

      if (!mounted) return;

      if (success) {
        _showSnackBar('Connection test successful!', isError: false);
      } else {
        _showSnackBar('Connection test failed');
      }
    } catch (e) {
      print('Error testing connection: $e');
      if (!mounted) return;
      _showSnackBar('Test failed: $e');
    }
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('PikPak Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'PikPak Integration',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Send magnet links directly to your PikPak cloud storage.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 24),

          // Enable/Disable Toggle
          Card(
            child: SwitchListTile(
              title: const Text(
                'Enable PikPak Integration',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                _pikpakEnabled
                    ? 'PikPak button and tab are visible'
                    : 'PikPak button and tab are hidden',
                style: const TextStyle(fontSize: 13),
              ),
              value: _pikpakEnabled,
              onChanged: (value) async {
                await StorageService.setPikPakEnabled(value);
                setState(() {
                  _pikpakEnabled = value;
                });

                // Notify main page to update navigation immediately
                MainPageBridge.notifyIntegrationChanged();

                _showSnackBar(
                  value
                      ? 'PikPak integration enabled'
                      : 'PikPak integration disabled',
                  isError: false,
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Connection status
          Card(
            color: _isConnected ? Colors.green.shade50 : Colors.grey.shade50,
            child: ListTile(
              leading: Icon(
                _isConnected ? Icons.check_circle : Icons.circle_outlined,
                color: _isConnected ? Colors.green : Colors.grey,
              ),
              title: Text(_isConnected ? 'Connected' : 'Not Connected'),
              subtitle: Text(_isConnected
                  ? 'Connected as: ${_emailController.text}'
                  : 'Login with your PikPak account below'),
            ),
          ),

          const SizedBox(height: 24),

          if (!_isConnected) ...[
            const Text(
              'PikPak Account',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'your@email.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
              enabled: !_isConnecting,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                hintText: 'Your PikPak password',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              enabled: !_isConnecting,
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isConnecting ? null : _login,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(_isConnecting ? 'Logging in...' : 'Login'),
            ),
          ] else ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _testConnection,
              icon: const Icon(Icons.cloud_done),
              label: const Text('Test Connection'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
          ],

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          const Text(
            'How It Works',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '1. Login with your PikPak account above\n'
            '2. Search for torrents in the app\n'
            '3. Click "PikPak" on any torrent\n'
            '4. Magnet link is sent to your PikPak cloud\n'
            '5. PikPak downloads the torrent to your cloud storage\n'
            '6. Access and play files from PikPak tab',
            style: TextStyle(fontSize: 14),
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),

          const Text(
            'About PikPak',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'PikPak is a cloud storage service that supports offline downloads from magnet links and torrents. Files are stored in your PikPak cloud and can be streamed or downloaded.',
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}
