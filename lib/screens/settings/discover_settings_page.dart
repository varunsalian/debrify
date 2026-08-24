import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../services/storage_service.dart';
import '../../services/stremio_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';

/// Discover behavior settings. Source options mirror the Discover dropdown:
/// fixed tracker/CW sources first, followed by installed browsable add-ons.
class DiscoverSettingsPage extends StatefulWidget {
  final Future<bool> Function()? mdblistAuthLoader;
  final Future<List<StremioAddon>> Function()? addonLoader;

  const DiscoverSettingsPage({
    super.key,
    this.mdblistAuthLoader,
    this.addonLoader,
  });

  @override
  State<DiscoverSettingsPage> createState() => _DiscoverSettingsPageState();
}

class _DiscoverSettingsPageState extends State<DiscoverSettingsPage> {
  bool _loading = true;
  String _defaultSource = StorageService.discoverDefaultRememberLast;
  List<SettingsSelectOption> _options = const [];
  final FocusNode _dropdownNode = FocusNode(
    debugLabel: 'discover-default-source',
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('discover_settings');
    _load();
  }

  @override
  void dispose() {
    _dropdownNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final defaultSource = await StorageService.getDiscoverDefaultSource();
    final options = <SettingsSelectOption>[
      const SettingsSelectOption(
        StorageService.discoverDefaultRememberLast,
        'Remember what was opened last time',
        'Reopen the source you last used in Discover',
      ),
      const SettingsSelectOption(
        'cw',
        'Continue Watching',
        'Always open your in-progress titles',
      ),
      const SettingsSelectOption(
        'trakt',
        'Trakt',
        'Always open Trakt browsing',
      ),
      const SettingsSelectOption(
        'simkl',
        'Simkl',
        'Always open Simkl browsing',
      ),
    ];

    var mdblistAuthenticated = false;
    if (kMdblistEnabled) {
      try {
        mdblistAuthenticated =
            await (widget.mdblistAuthLoader?.call() ??
                MdblistService.instance.isAuthenticated());
      } catch (_) {}
    }
    if (kMdblistEnabled &&
        (mdblistAuthenticated || defaultSource == 'mdblist')) {
      options.add(
        SettingsSelectOption(
          'mdblist',
          'MDBList',
          mdblistAuthenticated
              ? 'Always open MDBList browsing'
              : 'Connect MDBList to use this source again',
        ),
      );
    }

    try {
      final addons =
          await (widget.addonLoader?.call() ??
              StremioService.instance.getCatalogAddons());
      for (final addon in addons) {
        if (addon.catalogs.any((catalog) => catalog.isBrowsable)) {
          options.add(
            SettingsSelectOption(
              'a:${addon.id}',
              addon.name,
              'Always open this Stremio add-on',
            ),
          );
        }
      }
    } catch (_) {
      // Fixed options remain usable if add-on manifests cannot be loaded.
    }

    // Keep a configured but currently unavailable add-on visible. This avoids
    // silently changing the setting during a temporary manifest failure.
    if (!options.any((option) => option.value == defaultSource) &&
        defaultSource.startsWith('a:')) {
      options.add(
        SettingsSelectOption(
          defaultSource,
          'Unavailable add-on',
          'Install or enable this add-on to use it again',
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _defaultSource = defaultSource;
      _options = options;
      _loading = false;
    });
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final primary = FocusManager.instance.primaryFocus;
        if (mounted && (primary == null || primary is FocusScopeNode)) {
          _dropdownNode.requestFocus();
        }
      });
    }
  }

  Future<void> _select(String value) async {
    if (value == _defaultSource) return;
    setState(() => _defaultSource = value);
    await StorageService.setDiscoverDefaultSource(value);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Discover',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Discover',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.explore_rounded,
                  title: 'Discover',
                  subtitle: 'Choose what appears when you open Discover',
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: 'What should it display by default?',
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SettingsSelectDropdown(
                        options: _options,
                        value: _defaultSource,
                        onChanged: _select,
                        focusNode: _dropdownNode,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
