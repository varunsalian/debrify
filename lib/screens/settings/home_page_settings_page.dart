import 'package:flutter/material.dart';
import '../../models/stremio_addon.dart';
import '../../services/iptv_media_store.dart' show IptvListMeta;
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/stremio_service.dart';
import '../../services/trakt/trakt_list_source.dart';
import '../../services/trakt/trakt_service.dart';
import '../../services/analytics_service.dart';
import '../../utils/platform_util.dart';
import 'home_sections_filter_page.dart';
import 'tv_home_style_page.dart';
import 'widgets/settings_widgets.dart';

class HomePageSettingsPage extends StatefulWidget {
  const HomePageSettingsPage({super.key});

  @override
  State<HomePageSettingsPage> createState() => _HomePageSettingsPageState();
}

class _HomePageSettingsPageState extends State<HomePageSettingsPage> {
  // First interactive row — gets DPAD focus on TV when the page opens.
  final FocusNode _firstTileFocusNode = FocusNode(
    debugLabel: 'homeSettings-first',
  );
  bool _loading = true;
  String _selectedSourceType = 'catalog';
  bool _hideProviderCards = false;
  bool _continueWatchingEnabled = true;
  bool _trailerAutoplayEnabled = false;
  bool _heroTrailerEnabled = true;
  bool _ambientTrailerAudioEnabled = true;
  int _ambientTrailerVolume = 70;
  bool _tvTrailerUnderlayEnabled = true;
  String _tvHomeStyle = 'canvas';
  List<StremioAddon> _addons = [];

  /// TV home layout row (this page owns it now): open the picker, then
  /// re-read so the row caption matches what was chosen.
  Future<void> _openTvHomeStyle() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TvHomeStylePage()),
    );
    if (!mounted) return;
    final style = await StorageService.getTvHomeStyle();
    if (!mounted) return;
    setState(() => _tvHomeStyle = style);
  }

  /// Is this platform's one ambient-trailer surface on? Decides whether the
  /// shared sound + volume rows have anything to govern. Only ever one of the
  /// two is live (StorageService hard-offs the other), so this is a pick, not
  /// an OR — a stale stored `true` for the wrong platform can't leak through.
  /// The cached TV read is safe here: build() is gated on [_loading], and
  /// clearing it awaits getters that themselves await the TV probe.
  bool get _ambientTrailerEnabled => PlatformUtil.isTelevision
      ? (_heroTrailerEnabled || _trailerAutoplayEnabled)
      : _trailerAutoplayEnabled;

  /// The surface these controls READ from. On TV both surfaces exist now (Home
  /// hero and the Showcase detail page), and one pair of controls governs both
  /// — see [_setAmbientAudio]. Reading either gives the same answer because
  /// writes go to both.
  static AmbientTrailerSurface get _ambientSurface =>
      PlatformUtil.isTelevision
      ? AmbientTrailerSurface.homeHero
      : AmbientTrailerSurface.detail;

  /// Writes the sound preference to every ambient surface this platform has.
  ///
  /// The keys stay per-surface — a phone's stored value must never govern a TV
  /// box's hero — but on a television one control deliberately governs both,
  /// rather than the detail page silently inheriting the hero's preference,
  /// which is what a platform-keyed lookup would have done.
  Future<void> _setAmbientAudio(bool value) async {
    await StorageService.setAmbientTrailerAudioEnabled(
      AmbientTrailerSurface.detail,
      value,
    );
    if (PlatformUtil.isTelevision) {
      await StorageService.setAmbientTrailerAudioEnabled(
        AmbientTrailerSurface.homeHero,
        value,
      );
    }
  }

  Future<void> _setAmbientVolume(int value) async {
    await StorageService.setAmbientTrailerVolume(
      AmbientTrailerSurface.detail,
      value,
    );
    if (PlatformUtil.isTelevision) {
      await StorageService.setAmbientTrailerVolume(
        AmbientTrailerSurface.homeHero,
        value,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('home_page_settings');
    _loadSettings();
  }

  @override
  void dispose() {
    _firstTileFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);

    try {
      final addons = await StremioService.instance.getCatalogAddons();
      final sourceType = await StorageService.getHomeDefaultSourceType();
      final hideProviderCards = await StorageService.getHomeHideProviderCards();
      final continueWatchingEnabled =
          await StorageService.getHomeContinueWatchingEnabled();
      final trailerAutoplayEnabled =
          await StorageService.getDetailTrailerAutoplayEnabled();
      final heroTrailerEnabled =
          await StorageService.getHomeHeroTrailerEnabled();
      // One pair of controls governs every ambient surface this platform has,
      // so the two stored values must not be allowed to diverge — a TV that had
      // sound off for its hero would otherwise show "off" while the newly
      // enabled detail trailer played at its own default of on. Read the shown
      // surface, then write it through to the other.
      final ambientTrailerAudioEnabled =
          await StorageService.getAmbientTrailerAudioEnabled(
            _ambientSurface,
          );
      final ambientTrailerVolume = await StorageService.getAmbientTrailerVolume(
        _ambientSurface,
      );
      if (PlatformUtil.isTelevision) {
        await _setAmbientAudio(ambientTrailerAudioEnabled);
        await _setAmbientVolume(ambientTrailerVolume);
      }
      final tvTrailerUnderlayEnabled =
          await StorageService.getTvTrailerUnderlayEnabled();
      final tvHomeStyle = await StorageService.getTvHomeStyle();

      // Only the two views that the current Home screen can render are valid.
      // Migrate the former All, Addon, Trakt, and other retired choices to
      // Catalog so existing installs get the new default.
      const validSourceTypes = {'catalog', 'keyword'};
      final normalizedSourceType = validSourceTypes.contains(sourceType)
          ? sourceType!
          : 'catalog';
      // Persist the coercion so a dropped preference doesn't silently linger.
      // Only when there was an actual stale value — not for a fresh install
      // (null), which already defaults to Catalog without needing a write.
      if (sourceType != null && normalizedSourceType != sourceType) {
        await StorageService.setHomeDefaultSourceType(normalizedSourceType);
      }

      if (!mounted) return;
      setState(() {
        _addons = addons;
        _selectedSourceType = normalizedSourceType;
        _hideProviderCards = hideProviderCards;
        _continueWatchingEnabled = continueWatchingEnabled;
        _trailerAutoplayEnabled = trailerAutoplayEnabled;
        _heroTrailerEnabled = heroTrailerEnabled;
        _ambientTrailerAudioEnabled = ambientTrailerAudioEnabled;
        // Off-grid stored values are injected as an extra dropdown option
        // (see _volumeOptions), so nothing silently changes on load.
        _ambientTrailerVolume = ambientTrailerVolume;
        _tvTrailerUnderlayEnabled = tvTrailerUnderlayEnabled;
        _tvHomeStyle = tvHomeStyle;
        _loading = false;
      });
      // TV: land DPAD focus on the first row so users aren't stranded.
      if (PlatformUtil.isTelevision) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Don't yank focus if it already landed on a real node (only the
          // route's FocusScope holds focus while nothing is focused yet).
          final primary = FocusManager.instance.primaryFocus;
          if (primary != null && primary is! FocusScopeNode) return;
          _firstTileFocusNode.requestFocus();
        });
      }
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
      MainPageBridge.notifyHomeSettingsChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save setting: $e')));
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

  /// True while the Home Rows manager's inputs are being gathered (the Trakt
  /// user-lists fetch can take a few seconds) — renders a busy subtitle on
  /// the tile and drops re-taps.
  bool _gatheringHomeRows = false;

  /// Open the two-pane Home Rows manager (which rows/catalogs appear on the
  /// Home board). Feeds it the same browsable catalog tree the board uses,
  /// plus the opt-in extras and their dynamic leaf data — the user's Trakt
  /// custom/liked lists (authenticated only, bounded, tolerated to fail:
  /// enabled entries then show as unavailable leaves) and the IPTV lists.
  /// Notifies the board to rebuild if anything changed.
  Future<void> _openHomeRowsManager() async {
    if (_gatheringHomeRows) return;
    setState(() => _gatheringHomeRows = true);
    try {
      final tree = [
        for (final a in _addons)
          (addon: a, catalogs: a.catalogs.where((c) => c.isBrowsable).toList()),
      ].where((e) => e.catalogs.isNotEmpty).toList();
      final disabled = await StorageService.getHomeDisabledSections();
      final extras = await StorageService.getHomeExtraRows();
      var iptvLists = const <IptvListMeta>[];
      try {
        iptvLists = await StorageService.getIptvLists();
      } catch (_) {
        // Enabled iptvlist: entries surface as unavailable leaves.
      }
      var traktUserLists = const <TraktListChoice>[];
      try {
        if (await TraktService.instance.isAuthenticated()) {
          traktUserLists = await TraktListSource.instance
              .loadUserLists()
              .timeout(const Duration(seconds: 5), onTimeout: () => const []);
        }
      } catch (_) {
        // Same: enabled custom/liked entries become unavailable leaves.
      }
      if (!mounted) return;
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => HomeSectionsFilterPage(
            catalogTree: tree,
            disabled: Set.of(disabled),
            extraRows: extras,
            traktUserLists: traktUserLists,
            iptvLists: iptvLists,
            isTelevision: PlatformUtil.isTelevision,
          ),
        ),
      );
      if (changed == true) MainPageBridge.notifyHomeSettingsChanged();
    } finally {
      if (mounted) setState(() => _gatheringHomeRows = false);
    }
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
                  title: 'Home Screen',
                  subtitle: 'Layout, rows, and what shows when the app opens',
                ),
                const SizedBox(height: 24),

                // Everything about the home screen lives HERE — including the
                // TV layout picker, so "how does my home look" is one page.
                SettingsSection(
                  title: '',
                  children: [
                    // Unconditional now: phones and desktop choose between
                    // Classic and Spotlight (the picker narrows its own list
                    // off-TV), and gating on isAndroidTvCached silently hid
                    // the row on Apple TV. Off-TV the caption shows the
                    // RESOLVED style — a stored 'canvas' reads as Classic.
                    SettingsTile.spec(
                      SettingsRows.tvHomeStyle,
                      subtitle: tvHomeStyleLabel(
                        PlatformUtil.isTelevision
                            ? _tvHomeStyle
                            : effectiveOffTvHomeStyle(_tvHomeStyle),
                      ),
                      onTap: _openTvHomeStyle,
                      // Home Layout is now always the first tile, so it owns
                      // the entry focus node on every platform — the old
                      // conditional handoff to Home Rows is gone with the
                      // condition.
                      focusNode: _firstTileFocusNode,
                    ),
                    // Home Rows manager entry — hide/show individual rows.
                    // SettingsTile (not bare ListTile) so DPAD focus shows.
                    SettingsTile(
                      icon: Icons.dashboard_customize_rounded,
                      title: 'Home Rows',
                      subtitle: _gatheringHomeRows
                          ? 'Loading your lists…'
                          : 'Choose which rows appear on Home',
                      onTap: _openHomeRowsManager,
                    ),
                  ],
                ),
                if (!PlatformUtil.isTelevision) ...[
                  const SizedBox(height: 16),

                  // TV has separate Home and Search tabs, so a Home default
                  // view selector only applies to desktop and mobile.
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedSourceType,
                        decoration: InputDecoration(
                          labelText: 'Default view',
                          prefixIcon: Icon(
                            _iconForSourceType(_selectedSourceType),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'catalog',
                            child: Text('Catalog'),
                          ),
                          DropdownMenuItem(
                            value: 'keyword',
                            child: Text('Keyword'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) _selectSourceType(value);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Provider cards toggle
                SettingsSection(
                  title: '',
                  children: [
                    SettingsToggleTile(
                      icon: Icons.credit_card_off_rounded,
                      title: 'Hide Provider Cards',
                      subtitle:
                          'Hide debrid service status cards on the home screen',
                      value: _hideProviderCards,
                      onChanged: (value) => _toggleHideProviderCards(value),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Continue Watching toggle
                SettingsSection(
                  title: '',
                  children: [
                    SettingsToggleTile(
                      icon: Icons.history_rounded,
                      title: 'Continue Watching',
                      subtitle:
                          'Show and track recently watched items on the home screen',
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
                  ],
                ),
                const SizedBox(height: 16),

                // Ambient trailers. A television now has BOTH surfaces — the
                // Home hero spotlight and the Showcase detail page — so both
                // toggles are offered there; off-TV there is no hero, so only
                // the detail one appears. What used to make "one per platform"
                // necessary was the process's single video output, and that is
                // now enforced directly (VideoOutputLease) rather than by
                // arranging for only one surface to exist.
                //
                // The sound switch + volume below govern every surface this
                // platform has — one control, written to both keys.
                SettingsSection(
                  title: '',
                  children: [
                    if (PlatformUtil.isTelevision)
                      SettingsToggleTile(
                        icon: Icons.smart_display_rounded,
                        title: 'Trailer on Home Spotlight',
                        subtitle:
                            'When you rest on a title, its trailer plays in '
                            'the hero at the top of Home and in Discover.',
                        subtitleMaxLines: 2,
                        value: _heroTrailerEnabled,
                        onChanged: (value) async {
                          try {
                            await StorageService.setHomeHeroTrailerEnabled(
                              value,
                            );
                            if (!mounted) return;
                            setState(() => _heroTrailerEnabled = value);
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
                    SettingsToggleTile(
                        icon: Icons.movie_filter_rounded,
                        title: 'Trailer on Detail Page',
                        subtitle:
                            'Play a trailer behind the movie/series detail '
                            'page. Falls back to the poster when off or '
                            'unavailable.',
                        subtitleMaxLines: 2,
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
                    if (_ambientTrailerEnabled) ...[
                      SettingsToggleTile(
                        icon: Icons.volume_up_rounded,
                        title: 'Trailer Sound',
                        // Name the surface rather than say "the trailer" — the
                        // IPTV guide's live channel preview is a feed, not a
                        // trailer, and deliberately ignores this.
                        subtitle: PlatformUtil.isTelevision
                            ? 'Off plays the spotlight trailer silently.'
                            : 'Off plays the detail-page trailer silently.',
                        value: _ambientTrailerAudioEnabled,
                        onChanged: (value) async {
                          try {
                            await _setAmbientAudio(value);
                            if (!mounted) return;
                            setState(() => _ambientTrailerAudioEnabled = value);
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
                      if (_ambientTrailerAudioEnabled)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: _ambientTrailerVolume,
                            decoration: const InputDecoration(
                              labelText: 'Trailer volume',
                              prefixIcon: Icon(Icons.tune_rounded),
                            ),
                            items: [
                              for (final v in _volumeOptions(
                                _ambientTrailerVolume,
                              ))
                                DropdownMenuItem(value: v, child: Text('$v%')),
                            ],
                            onChanged: (value) async {
                              if (value == null) return;
                              try {
                                await _setAmbientVolume(value);
                                if (!mounted) return;
                                setState(() => _ambientTrailerVolume = value);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Failed to save setting: $e',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                    ],
                    // TV only: which surface the ambient trailers render on.
                    // Underlay (default) = native hardware plane behind a
                    // translucent Flutter surface, the smooth path; off =
                    // legacy Flutter-Texture compositing, the escape hatch.
                    if (PlatformUtil.isTelevision)
                      SettingsToggleTile(
                        icon: Icons.layers_rounded,
                        title: 'Native Trailer Surface',
                        subtitle:
                            'Render trailers on a hardware surface for smoother '
                            'playback. Turn off if trailers glitch. Takes '
                            'effect after restarting the app.',
                        subtitleMaxLines: 3,
                        value: _tvTrailerUnderlayEnabled,
                        onChanged: (value) async {
                          try {
                            await StorageService.setTvTrailerUnderlayEnabled(
                              value,
                            );
                            if (!mounted) return;
                            setState(() => _tvTrailerUnderlayEnabled = value);
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
                  ],
                ),
                if (!PlatformUtil.isTelevision) ...[
                  const SizedBox(height: 16),
                  SettingsInfoBanner(
                    text: _infoTextForSourceType(_selectedSourceType),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 10% steps plus the stored value (if it isn't one of them), so a
  /// stale/custom pref doesn't silently change when the page opens.
  List<int> _volumeOptions(int value) {
    final options = [for (int v = 10; v <= 100; v += 10) v];
    if (!options.contains(value)) {
      options
        ..add(value)
        ..sort();
    }
    return options;
  }

  IconData _iconForSourceType(String type) {
    switch (type) {
      case 'catalog':
        return Icons.apps;
      case 'keyword':
        return Icons.search;
      default:
        return Icons.apps;
    }
  }

  String _infoTextForSourceType(String type) {
    switch (type) {
      case 'catalog':
        return 'The home screen will open with your catalog rows. This is the default behavior.';
      case 'keyword':
        return 'The home screen will open in keyword search mode, ready for you to type a torrent search query.';
      default:
        return 'Choose which view appears first when you open the app.';
    }
  }
}
