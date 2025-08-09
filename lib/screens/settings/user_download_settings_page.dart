import 'package:flutter/material.dart';
import 'package:background_downloader/background_downloader.dart';
import '../../services/storage_service.dart';

class UserDownloadSettingsPage extends StatefulWidget {
  const UserDownloadSettingsPage({super.key});

  @override
  State<UserDownloadSettingsPage> createState() => _UserDownloadSettingsPageState();
}

class _UserDownloadSettingsPageState extends State<UserDownloadSettingsPage> {
  String? _defaultDownloadFolder;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uri = await StorageService.getDefaultDownloadUri();
    setState(() {
      _defaultDownloadFolder = uri;
      _loading = false;
    });
  }

  Future<void> _pickDefaultFolder() async {
    try {
      final uri = await FileDownloader().uri.pickDirectory();
      if (uri == null) return;
      await StorageService.saveDefaultDownloadUri(uri.toString());
      setState(() => _defaultDownloadFolder = uri.toString());
      _snack('Default download folder set');
    } catch (_) {
      _snack('Failed to pick folder', error: true);
    }
  }

  Future<void> _clearDefaultFolder() async {
    await StorageService.clearDefaultDownloadUri();
    setState(() => _defaultDownloadFolder = null);
    _snack('Default download folder cleared');
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('User Download Settings')),
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
                      Icon(Icons.folder, color: Theme.of(context).colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Default download folder',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      _defaultDownloadFolder ?? 'Not set',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _pickDefaultFolder,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Choose folder'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _defaultDownloadFolder == null ? null : _clearDefaultFolder,
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear'),
                        ),
                      ),
                    ],
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