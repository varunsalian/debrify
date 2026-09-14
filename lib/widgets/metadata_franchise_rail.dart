import 'package:flutter/material.dart';

import '../models/metadata_preferences.dart';
import '../models/stremio_addon.dart';
import '../services/main_page_bridge.dart';
import '../services/metadata_explore_service.dart';
import '../services/metadata_preferences_service.dart';
import '../services/profiles/profile_runtime.dart';
import 'catalog_item_tile.dart';

/// Optional movie-franchise section. It occupies no space and makes no remote
/// requests with the default metadata preferences.
class MetadataFranchiseRail extends StatefulWidget {
  const MetadataFranchiseRail({
    super.key,
    required this.item,
    required this.onOpen,
    required this.isTelevision,
    this.service,
  });
  final StremioMeta item;
  final ValueChanged<StremioMeta>? onOpen;
  final bool isTelevision;
  final MetadataExploreService? service;
  @override
  State<MetadataFranchiseRail> createState() => _MetadataFranchiseRailState();
}

class _MetadataFranchiseRailState extends State<MetadataFranchiseRail> {
  MetadataExploreData? _data;
  int _generation = 0;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    MetadataPreferencesService.revision.addListener(_load);
    ProfileRuntime.scope.addListener(_load);
    MainPageBridge.addHomeSettingsListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant MetadataFranchiseRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.type != widget.item.type ||
        (oldWidget.onOpen == null) != (widget.onOpen == null) ||
        oldWidget.service != widget.service) {
      _load();
    }
  }

  @override
  void dispose() {
    MetadataPreferencesService.revision.removeListener(_load);
    ProfileRuntime.scope.removeListener(_load);
    MainPageBridge.removeHomeSettingsListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final scope = ProfileRuntime.scope.value;
    setState(() {
      _data = null;
      _failed = false;
    });
    if (widget.item.type != 'movie' || widget.onOpen == null) return;
    var enabled = false;
    try {
      final prefs = await MetadataPreferencesService.load();
      enabled = prefs.features.contains(MetadataFeature.franchises);
      if (!mounted || generation != _generation || !enabled) return;
      final data = await (widget.service ?? MetadataExploreService.instance)
          .details(
            widget.item,
            prefs.copyWith(features: {MetadataFeature.franchises}),
          );
      if (!mounted ||
          generation != _generation ||
          scope != ProfileRuntime.scope.value) {
        return;
      }
      setState(() {
        _data = data;
        _failed = data.unavailable.contains(MetadataFeature.franchises);
      });
    } catch (_) {
      if (mounted &&
          generation == _generation &&
          scope == ProfileRuntime.scope.value &&
          enabled) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return TextButton(
        onPressed: _load,
        child: const Text('Could not load franchise. Retry'),
      );
    }
    final data = _data;
    if (data == null || data.franchise.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            data.franchiseName ?? 'Franchise',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: data.franchise.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => SizedBox(
                width: 140,
                child: CatalogItemTile(
                  key: ValueKey(data.franchise[i].id),
                  item: data.franchise[i],
                  isTelevision: widget.isTelevision,
                  focusNode: null,
                  hasBoundSource: false,
                  onOpen: () => widget.onOpen!(data.franchise[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
