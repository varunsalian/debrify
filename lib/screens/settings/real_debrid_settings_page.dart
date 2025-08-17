import 'package:flutter/material.dart';
import '../../services/storage_service.dart';
import '../../services/account_service.dart';
import '../../widgets/account_status_widget.dart';

class RealDebridSettingsPage extends StatefulWidget {
  const RealDebridSettingsPage({super.key});

  @override
  State<RealDebridSettingsPage> createState() => _RealDebridSettingsPageState();
}

class _RealDebridSettingsPageState extends State<RealDebridSettingsPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  String? _savedApiKey;
  String _fileSelection = 'largest';
  String _postTorrentAction = 'none';
  bool _isEditing = false;
  bool _obscure = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiKey = await StorageService.getApiKey();
    final selection = await StorageService.getFileSelection();
    final postAction = await StorageService.getPostTorrentAction();
    setState(() {
      _savedApiKey = apiKey;
      _fileSelection = selection;
      _postTorrentAction = postAction;
      _loading = false;
    });
    
    // Refresh user info if API key exists
    if (apiKey != null && apiKey.isNotEmpty) {
      await AccountService.refreshUserInfo();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  void _snack(String m, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: err ? Colors.red : null),
    );
  }

  Future<void> _saveKey() async {
    final txt = _apiKeyController.text.trim();
    if (txt.isEmpty) {
      _snack('Please enter a valid API key', err: true);
      return;
    }
    
    // Validate the API key
    final isValid = await AccountService.validateAndGetUserInfo(txt);
    if (!isValid) {
      _snack('Invalid API key. Please check and try again.', err: true);
      return;
    }
    
    await StorageService.saveApiKey(txt);
    setState(() {
      _savedApiKey = txt;
      _isEditing = false;
      _apiKeyController.clear();
    });
    _snack('API key saved and validated');
  }

  Future<void> _deleteKey() async {
    await StorageService.deleteApiKey();
    AccountService.clearUserInfo();
    setState(() {
      _savedApiKey = null;
      _isEditing = false;
      _apiKeyController.clear();
    });
    _snack('API key deleted');
  }

  Future<void> _saveSelection(String v) async {
    await StorageService.saveFileSelection(v);
    setState(() => _fileSelection = v);
    _snack('Preference saved');
  }

  Future<void> _savePostAction(String v) async {
    await StorageService.savePostTorrentAction(v);
    setState(() => _postTorrentAction = v);
    _snack('Preference saved');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Real Debrid Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.key, color: Theme.of(context).colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('API Key',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (_savedApiKey != null && !_isEditing)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 14),
                              SizedBox(width: 4),
                              Text('Connected', style: TextStyle(color: Colors.green, fontSize: 12)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_isEditing) ...[
                    TextField(
                      controller: _apiKeyController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Real Debrid API Key',
                        prefixIcon: const Icon(Icons.security),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _saveKey,
                            child: const Text('Save'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(() {
                              _isEditing = false;
                              _apiKeyController.clear();
                            }),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                    )
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
                              child: Text('••••••••••••••••••••••••••••••••',
                                  style: TextStyle(color: Colors.grey)),
                            ),
                            Icon(Icons.visibility_off, color: Colors.grey[500], size: 16),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() => _isEditing = true),
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
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            ),
                          ),
                        ],
                      )
                    ] else ...[
                      FilledButton.icon(
                        onPressed: () => setState(() => _isEditing = true),
                        icon: const Icon(Icons.add),
                        label: const Text('Add API Key'),
                      ),
                    ]
                  ]
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Account Information Card
          if (AccountService.currentUser != null) ...[
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.account_circle,
                            color: Theme.of(context).colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text('Account Information',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AccountStatusWidget(user: AccountService.currentUser!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.folder_open,
                          color: Theme.of(context).colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('Real Debrid File Selection',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose how Real Debrid handles file selection when adding torrents',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  RadioListTile<String>(
                    title: const Text('File with highest size'),
                    subtitle: const Text('Ideal for movies - selects the largest file'),
                    value: 'largest',
                    groupValue: _fileSelection,
                    onChanged: (v) => v == null ? null : _saveSelection(v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    title: const Text('All video files'),
                    subtitle: const Text('Selects all video files (mp4, mkv, avi, etc.) from the torrent'),
                    value: 'video',
                    groupValue: _fileSelection,
                    onChanged: (v) => v == null ? null : _saveSelection(v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    title: const Text('All files'),
                    subtitle: const Text('Downloads all files in the torrent'),
                    value: 'all',
                    groupValue: _fileSelection,
                    onChanged: (v) => v == null ? null : _saveSelection(v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.play_circle_outline,
                          color: Theme.of(context).colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('Post-Torrent Action',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose what happens after adding a torrent to Real Debrid',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  RadioListTile<String>(
                    title: const Text('None'),
                    subtitle: const Text('Do nothing after adding torrent (default)'),
                    value: 'none',
                    groupValue: _postTorrentAction,
                    onChanged: (v) => v == null ? null : _savePostAction(v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    title: const Text('Play video'),
                    subtitle: const Text('Automatically open video player'),
                    value: 'play',
                    groupValue: _postTorrentAction,
                    onChanged: (v) => v == null ? null : _savePostAction(v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    title: const Text('Download'),
                    subtitle: const Text('Start downloading to device'),
                    value: 'download',
                    groupValue: _postTorrentAction,
                    onChanged: (v) => v == null ? null : _savePostAction(v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.help_outline,
                          color: Theme.of(context).colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('How to get your API key',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '1. Visit: real-debrid.com/devices\n'
                    '2. Log in if prompted\n'
                    '3. Scroll down to find your API key\n'
                    '4. Copy the API key and paste it above',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.grey[600], height: 1.5),
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