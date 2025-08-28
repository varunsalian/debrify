import 'package:flutter/material.dart';
import '../../services/storage_service.dart';

class TorrentSettingsPage extends StatefulWidget {
  const TorrentSettingsPage({super.key});

  @override
  State<TorrentSettingsPage> createState() => _TorrentSettingsPageState();
}

class _TorrentSettingsPageState extends State<TorrentSettingsPage> {
  bool _defaultTorrentsCsvEnabled = true;
  bool _defaultPirateBayEnabled = true;
  int _maxTorrentsCsvResults = 50;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final torrentsCsvEnabled = await StorageService.getDefaultTorrentsCsvEnabled();
    final pirateBayEnabled = await StorageService.getDefaultPirateBayEnabled();
    final maxTorrentsCsvResults = await StorageService.getMaxTorrentsCsvResults();
    
    // Ensure the max results value is valid for the dropdown
    final validOptions = [25, 50, 75, 100, 125, 150, 175, 200, 250, 300, 350, 400, 450, 500];
    int validMaxResults = maxTorrentsCsvResults;
    if (!validOptions.contains(maxTorrentsCsvResults)) {
      // Find the closest valid option
      validMaxResults = validOptions.reduce((a, b) => (a - maxTorrentsCsvResults).abs() < (b - maxTorrentsCsvResults).abs() ? a : b);
      // Save the corrected value back to storage
      await StorageService.setMaxTorrentsCsvResults(validMaxResults);
    }
    
    setState(() {
      _defaultTorrentsCsvEnabled = torrentsCsvEnabled;
      _defaultPirateBayEnabled = pirateBayEnabled;
      _maxTorrentsCsvResults = validMaxResults;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Torrent Settings'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                            Icons.search_rounded,
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
                                'Search Engine Defaults',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Configure which search engines are enabled by default',
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

                  const SizedBox(height: 24),

                  // Search Engine Settings
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Default Search Engines',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Choose which search engines should be enabled by default when opening the search page',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Torrents CSV Setting
                          _buildEngineSetting(
                            title: 'Torrents CSV',
                            subtitle: 'Comprehensive database with pagination',
                            icon: Icons.search_rounded,
                            value: _defaultTorrentsCsvEnabled,
                            onChanged: (value) async {
                              await StorageService.setDefaultTorrentsCsvEnabled(value);
                              setState(() {
                                _defaultTorrentsCsvEnabled = value;
                              });
                            },
                          ),
                          
                          const SizedBox(height: 12),
                          
                                                    // The Pirate Bay Setting
                          _buildEngineSetting(
                            title: 'The Pirate Bay',
                            subtitle: 'Popular torrent site',
                            icon: Icons.sailing_rounded,
                            value: _defaultPirateBayEnabled,
                            onChanged: (value) async {
                              await StorageService.setDefaultPirateBayEnabled(value);
                              setState(() {
                                _defaultPirateBayEnabled = value;
                              });
                            },
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Info message
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: Theme.of(context).colorScheme.secondary,
                                  size: 18,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'These settings only affect the default state. You can still toggle engines on/off in the search page.',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                         ],
                       ),
                     ),
                   ),

                   const SizedBox(height: 24),

                   // Max Results Settings
                   Card(
                     elevation: 2,
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                     child: Padding(
                       padding: const EdgeInsets.all(16),
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Text(
                             'Max Results Settings',
                             style: Theme.of(context).textTheme.titleLarge?.copyWith(
                               fontWeight: FontWeight.bold,
                             ),
                           ),
                           const SizedBox(height: 8),
                           Text(
                             'Configure how many results to fetch from each search engine',
                             style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                               color: Theme.of(context).colorScheme.onSurfaceVariant,
                             ),
                           ),
                           const SizedBox(height: 16),
                           
                           // Torrents CSV Max Results
                           _buildMaxResultsDropdown(
                             title: 'Max Results from Torrents CSV',
                             subtitle: 'Higher numbers take longer to search',
                             value: _maxTorrentsCsvResults,
                             onChanged: (value) async {
                               await StorageService.setMaxTorrentsCsvResults(value);
                               setState(() {
                                 _maxTorrentsCsvResults = value;
                               });
                             },
                           ),
                           
                           const SizedBox(height: 12),
                           
                           // The Pirate Bay Max Results (disabled)
                           _buildMaxResultsDropdown(
                             title: 'Max Results from The Pirate Bay',
                             subtitle: 'Fixed at 100 results',
                             value: 100,
                             onChanged: null, // Disabled
                             enabled: false,
                           ),
                         ],
                       ),
                     ),
                   ),


                ],
              ),
            ),
    );
  }

  Widget _buildEngineSetting({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: value 
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
            : Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: value 
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value 
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                  : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: 18,
              color: value 
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: value 
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildMaxResultsDropdown({
    required String title,
    required String subtitle,
    required int value,
    required Function(int)? onChanged,
    bool enabled = true,
  }) {
    final options = [25, 50, 75, 100, 125, 150, 175, 200, 250, 300, 350, 400, 450, 500];
    
    // Ensure the value is valid for the dropdown
    int validValue = value;
    if (!options.contains(value)) {
      // Find the closest valid option
      validValue = options.reduce((a, b) => (a - value).abs() < (b - value).abs() ? a : b);
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled 
            ? Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3)
            : Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: enabled 
              ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: enabled 
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
                             child: DropdownButtonFormField<int>(
                 value: validValue,
                onChanged: (newValue) {
                  if (newValue != null) {
                    onChanged?.call(newValue);
                  }
                },
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: options.map((option) {
                  return DropdownMenuItem<int>(
                    value: option,
                    child: Text(
                      '$option results',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }).toList(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                dropdownColor: Theme.of(context).colorScheme.surface,
                icon: Icon(
                  Icons.arrow_drop_down,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
} 