import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/debrid_download.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';
import '../utils/formatters.dart';
import '../widgets/stat_chip.dart';

class DebridDownloadsScreen extends StatefulWidget {
  const DebridDownloadsScreen({super.key});

  @override
  State<DebridDownloadsScreen> createState() => _DebridDownloadsScreenState();
}

class _DebridDownloadsScreenState extends State<DebridDownloadsScreen> {
  List<DebridDownload> _downloads = [];
  bool _isLoading = false;
  String _errorMessage = '';
  String? _apiKey;

  @override
  void initState() {
    super.initState();
    _loadApiKeyAndDownloads();
  }

  Future<void> _loadApiKeyAndDownloads() async {
    final apiKey = await StorageService.getApiKey();
    
    setState(() {
      _apiKey = apiKey;
    });

    if (apiKey != null) {
      await _fetchDownloads(apiKey);
    } else {
      setState(() {
        _errorMessage = 'No API key configured. Please add your Real Debrid API key in Settings.';
      });
    }
  }

  Future<void> _fetchDownloads(String apiKey) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final downloads = await DebridService.getDownloads(apiKey);
      setState(() {
        _downloads = downloads;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _copyDownloadLink(String downloadLink) {
    Clipboard.setData(ClipboardData(text: downloadLink));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Download link copied to clipboard!'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.download,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Real Debrid Downloads',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your premium downloads from Real Debrid',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Refresh Button
          if (_apiKey != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : () => _fetchDownloads(_apiKey!),
                icon: _isLoading 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
                label: Text(_isLoading ? 'Loading...' : 'Refresh Downloads'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Content
          if (_isLoading) ...[
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading your downloads...'),
                ],
              ),
            ),
          ] else if (_errorMessage.isNotEmpty) ...[
            // Error State
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Error Loading Downloads',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.red[700],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red[600],
                    ),
                  ),
                  if (_apiKey == null) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Navigate to settings
                        setState(() {
                          // This will trigger navigation to settings
                        });
                      },
                      icon: const Icon(Icons.settings),
                      label: const Text('Go to Settings'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (_downloads.isEmpty) ...[
            // Empty State
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.download_done,
                    color: Colors.blue,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No Downloads Found',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[700],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your Real Debrid downloads will appear here',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.blue[600],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Downloads List
            Text(
              'Your Downloads (${_downloads.length})',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _downloads.length,
              itemBuilder: (context, index) {
                final download = _downloads[index];
                return _buildDownloadCard(download);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDownloadCard(DebridDownload download) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _copyDownloadLink(download.download),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // File Name
              Row(
                children: [
                  Expanded(
                    child: Text(
                      download.filename,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.copy,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // File Info
              Row(
                children: [
                  StatChip(
                    icon: Icons.storage,
                    text: Formatters.formatFileSize(download.filesize),
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  StatChip(
                    icon: Icons.web,
                    text: download.host,
                    color: Colors.green,
                  ),
                  if (download.type != null) ...[
                    const SizedBox(width: 8),
                    StatChip(
                      icon: Icons.high_quality,
                      text: download.type!,
                      color: Colors.purple,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              
              // Date
              Text(
                'Generated: ${Formatters.formatDateTime(download.generated)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              
              // Tap hint
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.copy,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Tap to copy download link',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
} 