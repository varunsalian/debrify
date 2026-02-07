import 'package:flutter/material.dart';
import '../../models/stremio_addon.dart';
import '../../services/storage_service.dart';
import '../../services/stremio_service.dart';

class HomePageSettingsPage extends StatefulWidget {
  const HomePageSettingsPage({super.key});

  @override
  State<HomePageSettingsPage> createState() => _HomePageSettingsPageState();
}

class _HomePageSettingsPageState extends State<HomePageSettingsPage> {
  bool _loading = true;
  String _selectedSourceType = 'all';
  String? _selectedAddonUrl;
  String? _selectedCatalogId;
  bool _hideProviderCards = false;
  String _favoritesTapAction = 'play';
  List<StremioAddon> _addons = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);

    try {
      final addons = await StremioService.instance.getCatalogAddons();
      final sourceType = await StorageService.getHomeDefaultSourceType();
      final addonUrl = await StorageService.getHomeDefaultAddonUrl();
      final catalogId = await StorageService.getHomeDefaultCatalogId();
      final hideProviderCards = await StorageService.getHomeHideProviderCards();
      final favoritesTapAction = await StorageService.getHomeFavoritesTapAction();

      setState(() {
        _addons = addons;
        _selectedSourceType = sourceType ?? 'all';
        _selectedAddonUrl = addonUrl;
        _selectedCatalogId = catalogId;
        _hideProviderCards = hideProviderCards;
        _favoritesTapAction = favoritesTapAction;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load settings: $e')),
        );
      }
    }
  }

  Future<void> _selectSourceType(String type) async {
    try {
      await StorageService.setHomeDefaultSourceType(type);
      setState(() {
        _selectedSourceType = type;
      });
      // If not addon, clear addon-specific settings
      if (type != 'addon') {
        await StorageService.setHomeDefaultAddonUrl(null);
        await StorageService.setHomeDefaultCatalogId(null);
        setState(() {
          _selectedAddonUrl = null;
          _selectedCatalogId = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setting: $e')),
        );
      }
    }
  }

  Future<void> _selectAddon(String? addonUrl) async {
    try {
      await StorageService.setHomeDefaultAddonUrl(addonUrl);
      // Auto-select first catalog of the chosen addon
      String? firstCatalogKey;
      if (addonUrl != null) {
        final addon = _addons.where((a) => a.manifestUrl == addonUrl).firstOrNull;
        if (addon != null && addon.catalogs.isNotEmpty) {
          firstCatalogKey = _catalogKey(addon.catalogs.first);
        }
      }
      await StorageService.setHomeDefaultCatalogId(firstCatalogKey);
      setState(() {
        _selectedAddonUrl = addonUrl;
        _selectedCatalogId = firstCatalogKey;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save addon selection: $e')),
        );
      }
    }
  }

  Future<void> _selectCatalog(String? catalogKey) async {
    try {
      await StorageService.setHomeDefaultCatalogId(catalogKey);
      setState(() {
        _selectedCatalogId = catalogKey;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save catalog selection: $e')),
        );
      }
    }
  }

  Future<void> _toggleHideProviderCards(bool value) async {
    try {
      await StorageService.setHomeHideProviderCards(value);
      setState(() {
        _hideProviderCards = value;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setting: $e')),
        );
      }
    }
  }

  Future<void> _selectFavoritesTapAction(String value) async {
    try {
      await StorageService.setHomeFavoritesTapAction(value);
      setState(() {
        _favoritesTapAction = value;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setting: $e')),
        );
      }
    }
  }

  StremioAddon? get _selectedAddon {
    if (_selectedAddonUrl == null) return null;
    return _addons.where((a) => a.manifestUrl == _selectedAddonUrl).firstOrNull;
  }

  /// Composite key for a catalog, unique within an addon (handles duplicate IDs across types)
  String _catalogKey(StremioAddonCatalog catalog) => '${catalog.type}:${catalog.id}';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Home Page Settings'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Page Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(
                      Icons.home_rounded,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Home Page Defaults',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Choose what shows first when the app opens',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Main settings card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Source type dropdown
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _selectedSourceType,
                      decoration: InputDecoration(
                        labelText: 'Default view',
                        prefixIcon: Icon(
                          _iconForSourceType(_selectedSourceType),
                          color: theme.colorScheme.primary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(value: 'keyword', child: Text('Keyword')),
                        DropdownMenuItem(value: 'addon', child: Text('Addon')),
                        DropdownMenuItem(value: 'iptv', child: Text('IPTV')),
                        DropdownMenuItem(value: 'reddit', child: Text('Reddit')),
                      ],
                      onChanged: (value) {
                        if (value != null) _selectSourceType(value);
                      },
                    ),

                    // Addon dropdown (shown when source type is 'addon')
                    if (_selectedSourceType == 'addon' && _addons.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _addons.any((a) => a.manifestUrl == _selectedAddonUrl)
                            ? _selectedAddonUrl
                            : null,
                        decoration: InputDecoration(
                          labelText: 'Addon',
                          prefixIcon: Icon(
                            Icons.extension,
                            color: theme.colorScheme.primary,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                        ),
                        items: _addons.map((addon) {
                          return DropdownMenuItem<String>(
                            value: addon.manifestUrl,
                            child: Text(
                              addon.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) => _selectAddon(value),
                      ),
                    ],

                    // Catalog dropdown (shown when addon is selected and has catalogs)
                    if (_selectedSourceType == 'addon' &&
                        _selectedAddon != null &&
                        _selectedAddon!.catalogs.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedAddon!.catalogs.any((c) => _catalogKey(c) == _selectedCatalogId)
                            ? _selectedCatalogId
                            : null,
                        decoration: InputDecoration(
                          labelText: 'Catalog',
                          prefixIcon: Icon(
                            Icons.view_list_rounded,
                            color: theme.colorScheme.primary,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                        ),
                        items: _selectedAddon!.catalogs.map((catalog) {
                          final typeLabel = catalog.type == 'movie'
                              ? 'Movie'
                              : catalog.type == 'series'
                                  ? 'Series'
                                  : catalog.type;
                          return DropdownMenuItem<String>(
                            value: _catalogKey(catalog),
                            child: Text(
                              '${catalog.name} ($typeLabel)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) => _selectCatalog(value),
                      ),
                    ],

                    // No addons message
                    if (_selectedSourceType == 'addon' && _addons.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          'No catalog addons installed. Install addons from the Stremio Addons page first.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Provider cards toggle
            Card(
              child: SwitchListTile(
                secondary: Icon(
                  Icons.credit_card_off_rounded,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Hide Provider Cards'),
                subtitle: const Text(
                  'Hide debrid service status cards on the home screen',
                ),
                value: _hideProviderCards,
                onChanged: (value) => _toggleHideProviderCards(value),
              ),
            ),
            const SizedBox(height: 16),

            // Favorites tap action
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _favoritesTapAction,
                  decoration: InputDecoration(
                    labelText: 'Favorite tap action',
                    prefixIcon: Icon(
                      _favoritesTapAction == 'view_files'
                          ? Icons.folder_open_rounded
                          : Icons.play_arrow_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'play', child: Text('Play')),
                    DropdownMenuItem(value: 'view_files', child: Text('View Files')),
                  ],
                  onChanged: (value) {
                    if (value != null) _selectFavoritesTapAction(value);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Info card
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _infoTextForSourceType(_selectedSourceType),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
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

  IconData _iconForSourceType(String type) {
    switch (type) {
      case 'all':
        return Icons.apps;
      case 'keyword':
        return Icons.search;
      case 'addon':
        return Icons.extension;
      case 'iptv':
        return Icons.live_tv;
      case 'reddit':
        return Icons.play_circle_outline;
      default:
        return Icons.apps;
    }
  }

  String _infoTextForSourceType(String type) {
    switch (type) {
      case 'all':
        return 'The home screen will show your favorites from Playlist, IPTV, and Debrify TV. This is the default behavior.';
      case 'keyword':
        return 'The home screen will open in keyword search mode, ready for you to type a torrent search query.';
      case 'addon':
        return 'The home screen will open directly to the selected addon\'s catalog, showing its content immediately.';
      case 'iptv':
        return 'The home screen will open in IPTV mode, showing your M3U playlist channels.';
      case 'reddit':
        return 'The home screen will open in Reddit mode, showing video content from subreddits.';
      default:
        return 'Choose which view appears first when you open the app.';
    }
  }
}
