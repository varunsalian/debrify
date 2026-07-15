import 'package:flutter/material.dart';
import '../../models/stremio_addon.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/stremio_service.dart';
import '../../utils/platform_util.dart';
import 'home_sections_filter_page.dart';
import 'widgets/settings_widgets.dart';

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
  String _selectedTraktListType = 'progress';
  String _selectedTraktContentType = 'movies';
  bool _hideProviderCards = false;
  bool _continueWatchingEnabled = true;
  bool _trailerAutoplayEnabled = false;
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
      final continueWatchingEnabled =
          await StorageService.getHomeContinueWatchingEnabled();
      final trailerAutoplayEnabled =
          await StorageService.getDetailTrailerAutoplayEnabled();
      final traktListType = await StorageService.getHomeDefaultTraktListType();
      final traktContentType =
          await StorageService.getHomeDefaultTraktContentType();

      // Coerce any stale/unsupported saved value to a valid option so the
      // dropdown can't crash. IPTV and YouTube are no longer default-view
      // options (they moved to their own "Browse" tabs), so a previously-saved
      // 'iptv'/'youtube' — like the long-hidden 'reddit' — normalizes to 'all'.
      const validSourceTypes = {'all', 'keyword', 'addon', 'trakt'};
      final normalizedSourceType = validSourceTypes.contains(sourceType)
          ? sourceType!
          : 'all';
      // Persist the coercion so a dropped preference doesn't silently linger.
      // Only when there was an actual stale value — not for a fresh install
      // (null), which already defaults to 'all' without needing a write.
      if (sourceType != null && normalizedSourceType != sourceType) {
        await StorageService.setHomeDefaultSourceType(normalizedSourceType);
      }

      if (!mounted) return;
      setState(() {
        _addons = addons;
        _selectedSourceType = normalizedSourceType;
        _selectedAddonUrl = addonUrl;
        _selectedCatalogId = catalogId;
        _selectedTraktListType = traktListType ?? 'progress';
        _selectedTraktContentType = traktContentType ?? 'movies';
        _hideProviderCards = hideProviderCards;
        _continueWatchingEnabled = continueWatchingEnabled;
        _trailerAutoplayEnabled = trailerAutoplayEnabled;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load settings: $e')));
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
      // If not trakt, clear trakt-specific settings
      if (type != 'trakt') {
        await StorageService.setHomeDefaultTraktListType(null);
        await StorageService.setHomeDefaultTraktContentType(null);
        setState(() {
          _selectedTraktListType = 'progress';
          _selectedTraktContentType = 'movies';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save setting: $e')));
      }
    }
  }

  Future<void> _selectAddon(String? addonUrl) async {
    try {
      await StorageService.setHomeDefaultAddonUrl(addonUrl);
      // Auto-select first catalog of the chosen addon
      String? firstCatalogKey;
      if (addonUrl != null) {
        final addon = _addons
            .where((a) => a.manifestUrl == addonUrl)
            .firstOrNull;
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
      if (!mounted) return;
      setState(() {
        _hideProviderCards = value;
      });
      MainPageBridge.notifyHomeSettingsChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save setting: $e')));
      }
    }
  }

  StremioAddon? get _selectedAddon {
    if (_selectedAddonUrl == null) return null;
    return _addons.where((a) => a.manifestUrl == _selectedAddonUrl).firstOrNull;
  }

  /// Composite key for a catalog, unique within an addon (handles duplicate IDs across types)
  String _catalogKey(StremioAddonCatalog catalog) =>
      '${catalog.type}:${catalog.id}';

  /// Open the two-pane Home Rows manager (which rows/catalogs appear on the
  /// Home board). Feeds it the same browsable catalog tree the board uses;
  /// notifies the board to rebuild if anything changed.
  Future<void> _openHomeRowsManager() async {
    final tree = [
      for (final a in _addons)
        (
          addon: a,
          catalogs: a.catalogs.where((c) => c.isBrowsable).toList(),
        ),
    ].where((e) => e.catalogs.isNotEmpty).toList();
    final disabled = await StorageService.getHomeDisabledSections();
    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HomeSectionsFilterPage(
          catalogTree: tree,
          disabled: Set.of(disabled),
          isTelevision: PlatformUtil.isAndroidTvCached,
        ),
      ),
    );
    if (changed == true) MainPageBridge.notifyHomeSettingsChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Home Page Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Home Page Settings',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.home_rounded,
                  title: 'Home Page Defaults',
                  subtitle: 'Choose what shows first when the app opens',
                ),
                const SizedBox(height: 24),

                // Home Rows manager entry — hide/show individual Home rows.
                Card(
                  child: ListTile(
                    leading:
                        const Icon(Icons.dashboard_customize_rounded),
                    title: const Text('Home Rows'),
                    subtitle:
                        const Text('Choose which rows appear on Home'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openHomeRowsManager,
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
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All')),
                            DropdownMenuItem(
                              value: 'keyword',
                              child: Text('Keyword'),
                            ),
                            DropdownMenuItem(
                              value: 'addon',
                              child: Text('Addon'),
                            ),
                            DropdownMenuItem(
                              value: 'trakt',
                              child: Text('Trakt'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) _selectSourceType(value);
                          },
                        ),

                        // Addon dropdown (shown when source type is 'addon')
                        if (_selectedSourceType == 'addon' &&
                            _addons.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value:
                                _addons.any(
                                  (a) => a.manifestUrl == _selectedAddonUrl,
                                )
                                ? _selectedAddonUrl
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Addon',
                              prefixIcon: Icon(Icons.extension),
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
                            value:
                                _selectedAddon!.catalogs.any(
                                  (c) => _catalogKey(c) == _selectedCatalogId,
                                )
                                ? _selectedCatalogId
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Catalog',
                              prefixIcon: Icon(Icons.view_list_rounded),
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

                        // Trakt list type dropdown (shown when source type is 'trakt')
                        if (_selectedSourceType == 'trakt') ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _selectedTraktListType,
                            decoration: const InputDecoration(
                              labelText: 'List',
                              prefixIcon: Icon(Icons.list_rounded),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'progress',
                                child: Text('Continue Watching'),
                              ),
                              DropdownMenuItem(
                                value: 'watchlist',
                                child: Text('Watchlist'),
                              ),
                              DropdownMenuItem(
                                value: 'history',
                                child: Text('History'),
                              ),
                              DropdownMenuItem(
                                value: 'collection',
                                child: Text('Collection'),
                              ),
                              DropdownMenuItem(
                                value: 'ratings',
                                child: Text('Ratings'),
                              ),
                              DropdownMenuItem(
                                value: 'trending',
                                child: Text('Trending'),
                              ),
                              DropdownMenuItem(
                                value: 'popular',
                                child: Text('Popular'),
                              ),
                              DropdownMenuItem(
                                value: 'anticipated',
                                child: Text('Anticipated'),
                              ),
                              DropdownMenuItem(
                                value: 'recommendations',
                                child: Text('Recommendations'),
                              ),
                              DropdownMenuItem(
                                value: 'likedLists',
                                child: Text('Liked Lists'),
                              ),
                            ],
                            onChanged: (value) async {
                              if (value == null) return;
                              await StorageService.setHomeDefaultTraktListType(
                                value,
                              );
                              setState(() => _selectedTraktListType = value);
                            },
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _selectedTraktContentType,
                            decoration: InputDecoration(
                              labelText: 'Content type',
                              prefixIcon: Icon(
                                _selectedTraktContentType == 'movies'
                                    ? Icons.movie_outlined
                                    : Icons.tv_rounded,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'movies',
                                child: Text('Movies'),
                              ),
                              DropdownMenuItem(
                                value: 'shows',
                                child: Text('Shows'),
                              ),
                            ],
                            onChanged: (value) async {
                              if (value == null) return;
                              await StorageService.setHomeDefaultTraktContentType(
                                value,
                              );
                              setState(() => _selectedTraktContentType = value);
                            },
                          ),
                        ],

                        // No addons message
                        if (_selectedSourceType == 'addon' && _addons.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: Text(
                              'No catalog addons installed. Install addons from the Stremio Addons page first.',
                              style: TextStyle(
                                fontSize: 13,
                                color: kSettingsRed,
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
                    secondary: const Icon(Icons.credit_card_off_rounded),
                    title: const Text('Hide Provider Cards'),
                    subtitle: const Text(
                      'Hide debrid service status cards on the home screen',
                    ),
                    value: _hideProviderCards,
                    onChanged: (value) => _toggleHideProviderCards(value),
                  ),
                ),
                const SizedBox(height: 16),

                // Continue Watching toggle
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.history_rounded),
                    title: const Text('Continue Watching'),
                    subtitle: const Text(
                      'Show and track recently watched items on the home screen',
                    ),
                    value: _continueWatchingEnabled,
                    onChanged: (value) async {
                      try {
                        await StorageService.setHomeContinueWatchingEnabled(
                          value,
                        );
                        if (!mounted) return;
                        setState(() => _continueWatchingEnabled = value);
                        MainPageBridge.notifyHomeSettingsChanged();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to save setting: $e'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Trailer autoplay toggle
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.movie_filter_rounded),
                    title: const Text('Autoplay Trailers'),
                    subtitle: const Text(
                      'Play a trailer (with sound) behind the movie/series detail '
                      'page. '
                      'Falls back to the poster when off or unavailable.',
                    ),
                    value: _trailerAutoplayEnabled,
                    onChanged: (value) async {
                      try {
                        await StorageService.setDetailTrailerAutoplayEnabled(
                          value,
                        );
                        if (!mounted) return;
                        setState(() => _trailerAutoplayEnabled = value);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to save setting: $e'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Info banner
                SettingsInfoBanner(
                  text: _infoTextForSourceType(_selectedSourceType),
                ),
              ],
            ),
          ),
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
      case 'trakt':
        return Icons.movie_filter_rounded;
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
      case 'trakt':
        return 'The home screen will open in Trakt mode, showing your watchlist, continue watching, and more.';
      default:
        return 'Choose which view appears first when you open the app.';
    }
  }
}
