import 'package:flutter/material.dart';
import '../../services/storage_service.dart';

class DebrifyTvSettingsPage extends StatefulWidget {
  const DebrifyTvSettingsPage({super.key});

  @override
  State<DebrifyTvSettingsPage> createState() => _DebrifyTvSettingsPageState();
}

class _DebrifyTvSettingsPageState extends State<DebrifyTvSettingsPage> {
  // Search engines
  bool _useTorrentsCsv = true;
  bool _usePirateBay = true;
  bool _useYts = false;
  bool _useSolidTorrents = false;

  // Channel limits - Small
  int _channelSmallTorrentsCsvMax = 100;
  int _channelSmallSolidTorrentsMax = 100;
  int _channelSmallYtsMax = 50;

  // Channel limits - Large
  int _channelLargeTorrentsCsvMax = 25;
  int _channelLargeSolidTorrentsMax = 100;
  int _channelLargeYtsMax = 50;

  // Quick Play limits
  int _quickPlayTorrentsCsvMax = 500;
  int _quickPlaySolidTorrentsMax = 200;
  int _quickPlayYtsMax = 50;
  int _quickPlayMaxKeywords = 5;

  // General settings
  int _channelBatchSize = 4;
  int _keywordThreshold = 10;
  int _minTorrentsPerKeyword = 5;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // Search engines
    final useTorrentsCsv = await StorageService.getDebrifyTvUseTorrentsCsv();
    final usePirateBay = await StorageService.getDebrifyTvUsePirateBay();
    final useYts = await StorageService.getDebrifyTvUseYts();
    final useSolidTorrents = await StorageService.getDebrifyTvUseSolidTorrents();

    // Channel limits - Small
    final channelSmallTorrentsCsvMax = await StorageService.getDebrifyTvChannelSmallTorrentsCsvMax();
    final channelSmallSolidTorrentsMax = await StorageService.getDebrifyTvChannelSmallSolidTorrentsMax();
    final channelSmallYtsMax = await StorageService.getDebrifyTvChannelSmallYtsMax();

    // Channel limits - Large
    final channelLargeTorrentsCsvMax = await StorageService.getDebrifyTvChannelLargeTorrentsCsvMax();
    final channelLargeSolidTorrentsMax = await StorageService.getDebrifyTvChannelLargeSolidTorrentsMax();
    final channelLargeYtsMax = await StorageService.getDebrifyTvChannelLargeYtsMax();

    // Quick Play limits
    final quickPlayTorrentsCsvMax = await StorageService.getDebrifyTvQuickPlayTorrentsCsvMax();
    final quickPlaySolidTorrentsMax = await StorageService.getDebrifyTvQuickPlaySolidTorrentsMax();
    final quickPlayYtsMax = await StorageService.getDebrifyTvQuickPlayYtsMax();
    final quickPlayMaxKeywords = await StorageService.getDebrifyTvQuickPlayMaxKeywords();

    // General settings
    final channelBatchSize = await StorageService.getDebrifyTvChannelBatchSize();
    final keywordThreshold = await StorageService.getDebrifyTvKeywordThreshold();
    final minTorrentsPerKeyword = await StorageService.getDebrifyTvMinTorrentsPerKeyword();

    setState(() {
      _useTorrentsCsv = useTorrentsCsv;
      _usePirateBay = usePirateBay;
      _useYts = useYts;
      _useSolidTorrents = useSolidTorrents;

      _channelSmallTorrentsCsvMax = channelSmallTorrentsCsvMax;
      _channelSmallSolidTorrentsMax = channelSmallSolidTorrentsMax;
      _channelSmallYtsMax = channelSmallYtsMax;

      _channelLargeTorrentsCsvMax = channelLargeTorrentsCsvMax;
      _channelLargeSolidTorrentsMax = channelLargeSolidTorrentsMax;
      _channelLargeYtsMax = channelLargeYtsMax;

      _quickPlayTorrentsCsvMax = quickPlayTorrentsCsvMax;
      _quickPlaySolidTorrentsMax = quickPlaySolidTorrentsMax;
      _quickPlayYtsMax = quickPlayYtsMax;
      _quickPlayMaxKeywords = quickPlayMaxKeywords;

      _channelBatchSize = channelBatchSize;
      _keywordThreshold = keywordThreshold;
      _minTorrentsPerKeyword = minTorrentsPerKeyword;

      _loading = false;
    });
  }

  Future<void> _resetToDefaults() async {
    await StorageService.setDebrifyTvUseTorrentsCsv(true);
    await StorageService.setDebrifyTvUsePirateBay(true);
    await StorageService.setDebrifyTvUseYts(false);
    await StorageService.setDebrifyTvUseSolidTorrents(false);

    await StorageService.setDebrifyTvChannelSmallTorrentsCsvMax(100);
    await StorageService.setDebrifyTvChannelSmallSolidTorrentsMax(100);
    await StorageService.setDebrifyTvChannelSmallYtsMax(50);

    await StorageService.setDebrifyTvChannelLargeTorrentsCsvMax(25);
    await StorageService.setDebrifyTvChannelLargeSolidTorrentsMax(100);
    await StorageService.setDebrifyTvChannelLargeYtsMax(50);

    await StorageService.setDebrifyTvQuickPlayTorrentsCsvMax(500);
    await StorageService.setDebrifyTvQuickPlaySolidTorrentsMax(200);
    await StorageService.setDebrifyTvQuickPlayYtsMax(50);
    await StorageService.setDebrifyTvQuickPlayMaxKeywords(5);

    await StorageService.setDebrifyTvChannelBatchSize(4);
    await StorageService.setDebrifyTvKeywordThreshold(10);
    await StorageService.setDebrifyTvMinTorrentsPerKeyword(5);

    await _loadSettings();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings reset to defaults')),
      );
    }
  }

  int _calculatePages(int maxResults, int perPage) {
    return (maxResults / perPage).ceil();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Debrify TV Settings'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debrify TV Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.tv_rounded,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Debrify TV Configuration',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Configure search engines and result limits',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Search Engines Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Search Engines',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select which engines to use for Debrify TV',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildEngineSetting(
                    title: 'Torrents CSV',
                    subtitle: '25 results/page • Pagination supported',
                    icon: Icons.table_chart,
                    value: _useTorrentsCsv,
                    onChanged: (value) async {
                      setState(() => _useTorrentsCsv = value);
                      await StorageService.setDebrifyTvUseTorrentsCsv(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildEngineSetting(
                    title: 'Pirate Bay',
                    subtitle: '~100-300 results • Single request',
                    icon: Icons.sailing,
                    value: _usePirateBay,
                    onChanged: (value) async {
                      setState(() => _usePirateBay = value);
                      await StorageService.setDebrifyTvUsePirateBay(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildEngineSetting(
                    title: 'YTS (Proxy)',
                    subtitle: '50 results/page • Uses Jina.ai proxy',
                    icon: Icons.movie_creation_rounded,
                    value: _useYts,
                    isProxy: true,
                    onChanged: (value) async {
                      setState(() => _useYts = value);
                      await StorageService.setDebrifyTvUseYts(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildEngineSetting(
                    title: 'SolidTorrents (Proxy)',
                    subtitle: '100 results/page • Uses Jina.ai proxy',
                    icon: Icons.storage_rounded,
                    value: _useSolidTorrents,
                    isProxy: true,
                    onChanged: (value) async {
                      setState(() => _useSolidTorrents = value);
                      await StorageService.setDebrifyTvUseSolidTorrents(value);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Channel Search Limits Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Channel Search Limits',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Control how many results to fetch per keyword based on channel size',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Small Channels
                  Text(
                    'Small Channels (< $_keywordThreshold keywords)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildMaxResultsDropdown(
                    title: 'Torrents CSV',
                    value: _channelSmallTorrentsCsvMax,
                    options: const [25, 50, 100, 200, 500],
                    perPage: 25,
                    enabled: _useTorrentsCsv,
                    onChanged: (value) async {
                      setState(() => _channelSmallTorrentsCsvMax = value);
                      await StorageService.setDebrifyTvChannelSmallTorrentsCsvMax(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildMaxResultsDropdown(
                    title: 'SolidTorrents',
                    value: _channelSmallSolidTorrentsMax,
                    options: const [100, 200, 300, 500],
                    perPage: 100,
                    enabled: _useSolidTorrents,
                    onChanged: (value) async {
                      setState(() => _channelSmallSolidTorrentsMax = value);
                      await StorageService.setDebrifyTvChannelSmallSolidTorrentsMax(value);
                    },
                  ),

                  const SizedBox(height: 24),

                  // Large Channels
                  Text(
                    'Large Channels (≥ $_keywordThreshold keywords)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildMaxResultsDropdown(
                    title: 'Torrents CSV',
                    value: _channelLargeTorrentsCsvMax,
                    options: const [25, 50, 100],
                    perPage: 25,
                    enabled: _useTorrentsCsv,
                    onChanged: (value) async {
                      setState(() => _channelLargeTorrentsCsvMax = value);
                      await StorageService.setDebrifyTvChannelLargeTorrentsCsvMax(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildMaxResultsDropdown(
                    title: 'SolidTorrents',
                    value: _channelLargeSolidTorrentsMax,
                    options: const [100, 200],
                    perPage: 100,
                    enabled: _useSolidTorrents,
                    onChanged: (value) async {
                      setState(() => _channelLargeSolidTorrentsMax = value);
                      await StorageService.setDebrifyTvChannelLargeSolidTorrentsMax(value);
                    },
                  ),

                  const SizedBox(height: 24),

                  // General Channel Settings
                  _buildMaxResultsDropdown(
                    title: 'Batch Size (Parallelism)',
                    subtitle: 'How many keywords to search at once',
                    value: _channelBatchSize,
                    options: const [2, 4, 6, 8, 10],
                    onChanged: (value) async {
                      setState(() => _channelBatchSize = value);
                      await StorageService.setDebrifyTvChannelBatchSize(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildMaxResultsDropdown(
                    title: 'Keyword Threshold',
                    subtitle: 'Switch from "small" to "large" mode',
                    value: _keywordThreshold,
                    options: const [5, 10, 15, 20, 25],
                    onChanged: (value) async {
                      setState(() => _keywordThreshold = value);
                      await StorageService.setDebrifyTvKeywordThreshold(value);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Quick Play Limits Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Play Limits',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Configure search limits for Quick Play',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildMaxResultsDropdown(
                    title: 'Torrents CSV',
                    value: _quickPlayTorrentsCsvMax,
                    options: const [100, 200, 300, 500],
                    perPage: 25,
                    enabled: _useTorrentsCsv,
                    onChanged: (value) async {
                      setState(() => _quickPlayTorrentsCsvMax = value);
                      await StorageService.setDebrifyTvQuickPlayTorrentsCsvMax(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildMaxResultsDropdown(
                    title: 'SolidTorrents',
                    value: _quickPlaySolidTorrentsMax,
                    options: const [100, 200, 300, 500],
                    perPage: 100,
                    enabled: _useSolidTorrents,
                    onChanged: (value) async {
                      setState(() => _quickPlaySolidTorrentsMax = value);
                      await StorageService.setDebrifyTvQuickPlaySolidTorrentsMax(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildMaxResultsDropdown(
                    title: 'YTS',
                    value: _quickPlayYtsMax,
                    options: const [50],
                    perPage: 50,
                    enabled: _useYts,
                    subtitle: 'Fixed at 50 results',
                    onChanged: null,
                  ),
                  const SizedBox(height: 12),
                  _buildMaxResultsDropdown(
                    title: 'Max Keywords Allowed',
                    value: _quickPlayMaxKeywords,
                    options: const [3, 5, 10, 15, 20],
                    onChanged: (value) async {
                      setState(() => _quickPlayMaxKeywords = value);
                      await StorageService.setDebrifyTvQuickPlayMaxKeywords(value);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Advanced Settings Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Advanced Settings',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildMaxResultsDropdown(
                    title: 'Min Torrents Per Keyword',
                    subtitle: 'Skip keyword if fewer results',
                    value: _minTorrentsPerKeyword,
                    options: const [1, 3, 5, 10, 15],
                    onChanged: (value) async {
                      setState(() => _minTorrentsPerKeyword = value);
                      await StorageService.setDebrifyTvMinTorrentsPerKeyword(value);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Info Section
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Estimated Impact (20 keywords)',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Small Channels:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '• Torrents CSV: ${_calculatePages(_channelSmallTorrentsCsvMax, 25) * 20} API calls (${_calculatePages(_channelSmallTorrentsCsvMax, 25)} pg × 20)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '• SolidTorrents: ${_calculatePages(_channelSmallSolidTorrentsMax, 100) * 20} API calls (${_calculatePages(_channelSmallSolidTorrentsMax, 100)} pg × 20)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Large Channels:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '• Torrents CSV: ${_calculatePages(_channelLargeTorrentsCsvMax, 25) * 20} API calls (${_calculatePages(_channelLargeTorrentsCsvMax, 25)} pg × 20)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '• SolidTorrents: ${_calculatePages(_channelLargeSolidTorrentsMax, 100) * 20} API calls (${_calculatePages(_channelLargeSolidTorrentsMax, 100)} pg × 20)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Higher limits = More results but slower\nLower limits = Faster but fewer results',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Reset Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetToDefaults,
              icon: const Icon(Icons.refresh),
              label: const Text('Reset to Defaults'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildEngineSetting({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    bool isProxy = false,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        secondary: Icon(icon),
        title: Row(
          children: [
            Text(title),
            if (isProxy) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'PROXY',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildMaxResultsDropdown({
    required String title,
    String? subtitle,
    required int value,
    required List<int> options,
    int? perPage,
    bool enabled = true,
    required ValueChanged<int>? onChanged,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (perPage != null && enabled) ...[
                    const SizedBox(height: 4),
                    Text(
                      '→ ${_calculatePages(value, perPage)} page${_calculatePages(value, perPage) != 1 ? 's' : ''} ($perPage per page)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            DropdownButton<int>(
              value: value,
              items: options
                  .map(
                    (option) => DropdownMenuItem(
                      value: option,
                      child: Text(option.toString()),
                    ),
                  )
                  .toList(),
              onChanged: enabled && onChanged != null
                  ? (int? newValue) {
                      if (newValue != null) {
                        onChanged(newValue);
                      }
                    }
                  : null,
              underline: Container(),
            ),
          ],
        ),
      ),
    );
  }
}
