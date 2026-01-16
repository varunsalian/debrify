import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/storage_service.dart';
import '../../services/pikpak_api_service.dart';

/// Provider settings page for configuring default torrent provider.
class ProviderSettingsPage extends StatefulWidget {
  const ProviderSettingsPage({super.key});

  @override
  State<ProviderSettingsPage> createState() => _ProviderSettingsPageState();
}

class _ProviderSettingsPageState extends State<ProviderSettingsPage> {
  bool _loading = true;
  String _selectedProvider = 'none';

  // Available providers based on connected services
  bool _torboxAvailable = false;
  bool _realDebridAvailable = false;
  bool _pikpakAvailable = false;

  // Focus nodes for D-pad navigation
  final List<FocusNode> _providerFocusNodes = [];
  int _focusedIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    for (final node in _providerFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    // Check which providers are available
    final torboxKey = await StorageService.getTorboxApiKey();
    final rdKey = await StorageService.getApiKey();
    final pikpakAuth = await PikPakApiService.instance.isAuthenticated();

    final torboxEnabled = await StorageService.getTorboxIntegrationEnabled();
    final rdEnabled = await StorageService.getRealDebridIntegrationEnabled();

    final torboxAvailable =
        torboxEnabled && torboxKey != null && torboxKey.isNotEmpty;
    final rdAvailable = rdEnabled && rdKey != null && rdKey.isNotEmpty;
    final pikpakAvailable = pikpakAuth;

    // Load current setting
    var currentProvider = await StorageService.getDefaultTorrentProvider();

    // If the saved provider is no longer available, reset to 'none'
    if (currentProvider == 'torbox' && !torboxAvailable) {
      currentProvider = 'none';
      await StorageService.setDefaultTorrentProvider('none');
    } else if (currentProvider == 'debrid' && !rdAvailable) {
      currentProvider = 'none';
      await StorageService.setDefaultTorrentProvider('none');
    } else if (currentProvider == 'pikpak' && !pikpakAvailable) {
      currentProvider = 'none';
      await StorageService.setDefaultTorrentProvider('none');
    }

    if (!mounted) return;

    // Initialize focus nodes for available providers
    _providerFocusNodes.clear();
    // +1 for "Ask every time" option
    final providerCount = 1 +
        (torboxAvailable ? 1 : 0) +
        (rdAvailable ? 1 : 0) +
        (pikpakAvailable ? 1 : 0);
    for (int i = 0; i < providerCount; i++) {
      final node = FocusNode(debugLabel: 'provider-$i');
      node.addListener(() => _onFocusChange(i));
      _providerFocusNodes.add(node);
    }

    if (mounted) {
      setState(() {
        _torboxAvailable = torboxAvailable;
        _realDebridAvailable = rdAvailable;
        _pikpakAvailable = pikpakAvailable;
        _selectedProvider = currentProvider;
        _loading = false;
      });
    }
  }

  void _onFocusChange(int index) {
    if (mounted) {
      setState(() {
        _focusedIndex =
            _providerFocusNodes[index].hasFocus ? index : _focusedIndex;
      });
    }
  }

  Future<void> _selectProvider(String provider) async {
    setState(() {
      _selectedProvider = provider;
    });
    await StorageService.setDefaultTorrentProvider(provider);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Provider Settings'),
          backgroundColor: Theme.of(context).colorScheme.surface,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final hasAnyProvider =
        _torboxAvailable || _realDebridAvailable || _pikpakAvailable;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Provider Settings'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              if (!hasAnyProvider) ...[
                _buildNoProvidersMessage(context),
              ] else ...[
                _buildSection(
                  context,
                  title: 'Default Torrent Provider',
                  subtitle:
                      'Choose which service to use when adding torrents',
                  children: _buildProviderOptions(),
                ),
                const SizedBox(height: 16),
                _buildInfoMessage(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
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
              Icons.cloud_sync_rounded,
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
                  'Provider Settings',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configure default provider for adding torrents',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer
                            .withValues(alpha: 0.7),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  List<Widget> _buildProviderOptions() {
    final List<Widget> options = [];
    int nodeIndex = 0;

    // Always show "Ask every time" option
    options.add(_ProviderOption(
      focusNode: _providerFocusNodes[nodeIndex],
      isFocused: _focusedIndex == nodeIndex,
      icon: Icons.help_outline_rounded,
      iconColor: Colors.grey,
      title: 'Ask every time',
      subtitle: 'Show provider selection dialog',
      selected: _selectedProvider == 'none',
      onSelected: () => _selectProvider('none'),
    ));
    nodeIndex++;

    // Torbox option
    if (_torboxAvailable) {
      options.add(const SizedBox(height: 8));
      options.add(_ProviderOption(
        focusNode: _providerFocusNodes[nodeIndex],
        isFocused: _focusedIndex == nodeIndex,
        icon: Icons.flash_on_rounded,
        iconColor: const Color(0xFF7C3AED),
        title: 'Torbox',
        subtitle: 'Fast cloud torrent service',
        selected: _selectedProvider == 'torbox',
        onSelected: () => _selectProvider('torbox'),
      ));
      nodeIndex++;
    }

    // Real-Debrid option
    if (_realDebridAvailable) {
      options.add(const SizedBox(height: 8));
      options.add(_ProviderOption(
        focusNode: _providerFocusNodes[nodeIndex],
        isFocused: _focusedIndex == nodeIndex,
        icon: Icons.cloud_rounded,
        iconColor: const Color(0xFFE50914),
        title: 'Real-Debrid',
        subtitle: 'Premium link generator',
        selected: _selectedProvider == 'debrid',
        onSelected: () => _selectProvider('debrid'),
      ));
      nodeIndex++;
    }

    // PikPak option
    if (_pikpakAvailable) {
      options.add(const SizedBox(height: 8));
      options.add(_ProviderOption(
        focusNode: _providerFocusNodes[nodeIndex],
        isFocused: _focusedIndex == nodeIndex,
        icon: Icons.folder_rounded,
        iconColor: const Color(0xFF0088CC),
        title: 'PikPak',
        subtitle: 'Cloud storage service',
        selected: _selectedProvider == 'pikpak',
        onSelected: () => _selectProvider('pikpak'),
      ));
    }

    return options;
  }

  Widget _buildNoProvidersMessage(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .errorContainer
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No providers connected',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Connect Real-Debrid, Torbox, or PikPak in Settings to use this feature.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoMessage(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.3),
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
              'You can also set this when adding a torrent by checking "Always use this provider".',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// D-pad compatible provider option widget
class _ProviderOption extends StatelessWidget {
  final FocusNode focusNode;
  final bool isFocused;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onSelected;

  const _ProviderOption({
    required this.focusNode,
    required this.isFocused,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          onSelected();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isFocused
                ? const Color(0xFF3B82F6)
                : selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.5)
                    : theme.colorScheme.outline.withValues(alpha: 0.2),
            width: isFocused ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onSelected,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    )
                  else
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.outline.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
