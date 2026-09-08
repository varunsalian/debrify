import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/metadata_preferences.dart';
import '../models/stremio_addon.dart';
import '../services/debrify_image_cache.dart';
import '../services/metadata_explore_service.dart';
import '../services/metadata_preferences_service.dart';
import '../services/profiles/profile_runtime.dart';
import '../services/tmdb_metadata_repository.dart';
import '../theme/widgets/parallax_focus.dart';
import '../utils/tv_keys.dart';
import 'collections/tmdb_attribution.dart';
import 'metadata_presentation_mixin.dart';

/// A title's Explore destination, with a compact cinematic hero and photo rails.
class MetadataExploreSpotlight extends StatefulWidget {
  const MetadataExploreSpotlight({
    super.key,
    required this.item,
    required this.preferences,
    required this.data,
    required this.loading,
    required this.failed,
    required this.isTelevision,
    required this.onRetry,
    required this.onEntity,
    required this.onDiscover,
    required this.titleBuilder,
  });
  final StremioMeta item;
  final MetadataPreferences preferences;
  final MetadataExploreData? data;
  final bool loading, failed, isTelevision;
  final VoidCallback onRetry, onDiscover;
  final void Function(String, Map<String, dynamic>) onEntity;
  final Widget Function(StremioMeta, FocusNode?) titleBuilder;
  @override
  State<MetadataExploreSpotlight> createState() =>
      _MetadataExploreSpotlightState();
}

class _MetadataExploreSpotlightState extends State<MetadataExploreSpotlight> {
  final _castKey = GlobalKey();
  final _studioKey = GlobalKey();
  final _watchKey = GlobalKey();
  final _franchiseKey = GlobalKey();
  final _sectionNodes = <String, FocusNode>{};
  final _castScroll = ScrollController();
  final _franchiseScroll = ScrollController();
  int _jumpGeneration = 0;
  String? _watchKind;
  DialogRoute<void>? _castDialog;
  int _dialogGeneration = 0;

  @override
  void initState() {
    super.initState();
    ProfileRuntime.scope.addListener(_invalidateDialog);
    MetadataPreferencesService.revision.addListener(_invalidateDialog);
  }

  @override
  void didUpdateWidget(covariant MetadataExploreSpotlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences ||
        oldWidget.item.id != widget.item.id) {
      _invalidateDialog();
    }
  }

  void _invalidateDialog() {
    ++_jumpGeneration;
    ++_dialogGeneration;
    final route = _castDialog;
    _castDialog = null;
    if (route == null) return;
    // Disposal and policy changes can occur during a build. Remove only this
    // dialog after the frame, never whatever route happens to be on top.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (navigator != null && route.isActive) navigator.removeRoute(route);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    ProfileRuntime.scope.removeListener(_invalidateDialog);
    MetadataPreferencesService.revision.removeListener(_invalidateDialog);
    _invalidateDialog();
    _castScroll.dispose();
    _franchiseScroll.dispose();
    for (final node in _sectionNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _jump(GlobalKey key, String name) async {
    final target = key.currentContext;
    if (target == null) return;
    final generation = ++_jumpGeneration;
    final rail = switch (name) {
      'cast' => _castScroll,
      'franchise' => _franchiseScroll,
      _ => null,
    };
    if (rail != null && rail.hasClients) rail.jumpTo(0);
    await Scrollable.ensureVisible(
      target,
      alignment: .08,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    // A lazy rail must lay out its first tile again before its node can focus.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        generation != _jumpGeneration ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final node = _sectionNodes[name];
    if (node?.context != null) node!.requestFocus();
  }

  Widget _heading(String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _photo(Map<String, dynamic> person, {FocusNode? node}) => _ExploreTile(
    node: node,
    onTap: () => widget.onEntity('person', person),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _ExploreImage(
            url: TmdbMetadataRepository.image(
              person['profile_path'],
              size: 'w342',
            ),
            icon: Icons.person_outline,
            fit: BoxFit.cover,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xEE09111B)],
                stops: [.35, 1],
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${person['name'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${person['character'] ?? person['job'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _allPeople(List<Map<String, dynamic>> people) async {
    if (_castDialog != null) return;
    final generation = _dialogGeneration;
    final scope = ProfileRuntime.scope.value;
    final revision = MetadataPreferencesService.revision.value;
    final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF101925),
        child: SizedBox(
          width: 1000,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Cast & crew',
                        style: TextStyle(fontSize: 24, color: Colors.white),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    childAspectRatio: .7,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                  ),
                  itemCount: people.length,
                  itemBuilder: (_, i) => _ExploreTile(
                    onTap: () {
                      if (!mounted ||
                          generation != _dialogGeneration ||
                          scope != ProfileRuntime.scope.value ||
                          revision !=
                              MetadataPreferencesService.revision.value) {
                        return;
                      }
                      Navigator.pop(dialogContext);
                      widget.onEntity('person', people[i]);
                    },
                    child: Column(
                      children: [
                        Expanded(
                          child: _ExploreImage(
                            url: TmdbMetadataRepository.image(
                              people[i]['profile_path'],
                              size: 'w342',
                            ),
                            icon: Icons.person_outline,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            '${people[i]['name'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    _castDialog = route;
    await Navigator.of(context, rootNavigator: true).push(route);
    if (identical(_castDialog, route)) _castDialog = null;
  }

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .045),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: .09)),
    ),
    child: child,
  );

  Widget _entity(String kind, Map<String, dynamic> row, {FocusNode? node}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _ExploreTile(
          node: node,
          onTap: () => widget.onEntity(kind, row),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 62,
                  height: 62,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _ExploreImage(
                      url: TmdbMetadataRepository.image(
                        row[kind == 'person' ? 'profile_path' : 'logo_path'],
                        size: 'w185',
                      ),
                      icon: kind == 'person'
                          ? Icons.person_outline
                          : Icons.business_outlined,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row['name'] ?? ''}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (row['job'] != null)
                        Text(
                          '${row['job']}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white60),
              ],
            ),
          ),
        ),
      );

  Future<void> _availabilityLink(String value) async {
    final uri = Uri.tryParse(value);
    if (uri?.scheme != 'https' ||
        !const {'www.themoviedb.org', 'themoviedb.org'}.contains(uri?.host)) {
      return;
    }
    var opened = false;
    try {
      opened = await launchUrl(uri!, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the browser.')),
      );
    }
  }

  Widget _watch(MetadataExploreData data) {
    const labels = {
      'flatrate': 'Subscription',
      'free': 'Free',
      'ads': 'With ads',
      'rent': 'Rent',
      'buy': 'Buy',
    };
    final kinds = labels.keys
        .where((k) => data.providers[k]?.isNotEmpty == true)
        .toList();
    final selected = kinds.contains(_watchKind)
        ? _watchKind
        : kinds.firstOrNull;
    final providers = data.providers[selected] ?? [];
    return _panel(
      Column(
        key: _watchKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            'Where to watch',
            trailing: Text(
              widget.preferences.region,
              style: const TextStyle(color: Colors.white60),
            ),
          ),
          if (kinds.isEmpty)
            const Text(
              'No availability information for this region.',
              style: TextStyle(color: Colors.white70),
            ),
          if (kinds.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in kinds)
                  ChoiceChip(
                    focusNode: kind == kinds.first
                        ? _sectionNodes.putIfAbsent('watch', FocusNode.new)
                        : null,
                    label: Text(
                      labels[kind]!,
                      style: const TextStyle(color: Colors.white),
                    ),
                    selected: selected == kind,
                    selectedColor: Colors.white.withValues(alpha: .16),
                    backgroundColor: Colors.white.withValues(alpha: .04),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: .12),
                    ),
                    onSelected: (_) => setState(() => _watchKind = kind),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 124,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: providers.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (_, i) => SizedBox(
                  width: 100,
                  child: _ExploreTile(
                    child: Column(
                      children: [
                        SizedBox(
                          width: 72,
                          height: 72,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _ExploreImage(
                              url: TmdbMetadataRepository.image(
                                providers[i]['logo_path'],
                                size: 'w185',
                              ),
                              icon: Icons.live_tv,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Text(
                            '${providers[i]['provider_name'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Availability via JustWatch · TMDB',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (data.providerLink != null)
            TextButton(
              onPressed: () => _availabilityLink(data.providerLink!),
              child: const Text('Check availability ↗'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final people = widget.preferences.features.contains(MetadataFeature.people)
        ? data?.people ?? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[];
    final cast = people.where((p) => p['job'] != 'Director').toList();
    final crew = people.where((p) => p['job'] == 'Director').toList();
    final companies =
        widget.preferences.features.contains(MetadataFeature.companies)
        ? data?.companies ?? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[];
    final networks =
        widget.preferences.features.contains(MetadataFeature.companies)
        ? data?.networks ?? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[];
    final watch =
        widget.preferences.features.contains(MetadataFeature.availability) &&
        data != null;
    final franchise =
        widget.preferences.features.contains(MetadataFeature.franchises) &&
        data?.franchise.isNotEmpty == true;
    return Scaffold(
      backgroundColor: const Color(0xFF0C1420),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            final gutter = compact ? 20.0 : 48.0;
            final personWidth = compact
                ? 165.0
                : (constraints.maxWidth / 6.7).clamp(170.0, 250.0);
            final hasStudio =
                crew.isNotEmpty || companies.isNotEmpty || networks.isNotEmpty;
            final studios = _panel(
              Column(
                key: _studioKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (crew.isNotEmpty) ...[
                    _heading('Behind the camera'),
                    for (final person in crew) _entity('person', person),
                  ],
                  if (companies.isNotEmpty || networks.isNotEmpty) ...[
                    _heading('Studios & networks'),
                    for (var i = 0; i < companies.length; i++)
                      _entity(
                        'company',
                        companies[i],
                        node: i == 0
                            ? _sectionNodes.putIfAbsent(
                                'studios',
                                FocusNode.new,
                              )
                            : null,
                      ),
                    for (var i = 0; i < networks.length; i++)
                      _entity(
                        'network',
                        networks[i],
                        node: companies.isEmpty && i == 0
                            ? _sectionNodes.putIfAbsent(
                                'studios',
                                FocusNode.new,
                              )
                            : null,
                      ),
                  ],
                ],
              ),
            );
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ExploreHero(
                    item: widget.item,
                    compact: compact,
                    gutter: gutter,
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            if (cast.isNotEmpty)
                              OutlinedButton(
                                onPressed: () => _jump(_castKey, 'cast'),
                                child: const Text('Cast & crew'),
                              ),
                            if (franchise)
                              OutlinedButton(
                                onPressed: () =>
                                    _jump(_franchiseKey, 'franchise'),
                                child: const Text('Franchise'),
                              ),
                            if (companies.isNotEmpty || networks.isNotEmpty)
                              OutlinedButton(
                                onPressed: () => _jump(_studioKey, 'studios'),
                                child: const Text('Studios'),
                              ),
                            if (watch)
                              OutlinedButton(
                                onPressed: () => _jump(_watchKey, 'watch'),
                                child: const Text('Where to watch'),
                              ),
                            if (widget.preferences.features.contains(
                              MetadataFeature.discovery,
                            ))
                              OutlinedButton.icon(
                                onPressed: widget.onDiscover,
                                icon: const Icon(Icons.explore_outlined),
                                label: const Text('Discover movies and shows'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (widget.loading)
                          data == null
                              ? const Center(child: CircularProgressIndicator())
                              : const LinearProgressIndicator(),
                        if (widget.failed ||
                            (!widget.loading &&
                                data?.unavailable.isNotEmpty == true))
                          TextButton(
                            onPressed: widget.onRetry,
                            child: Text(
                              data == null
                                  ? 'Could not load. Retry'
                                  : 'Some sections could not load. Retry',
                            ),
                          ),
                        if (cast.isNotEmpty) ...[
                          _heading(
                            'Cast & crew',
                            trailing: TextButton(
                              onPressed: () => _allPeople(people),
                              child: const Text('View all →'),
                            ),
                          ),
                          SizedBox(
                            key: _castKey,
                            height: personWidth * 1.3,
                            child: ListView.separated(
                              controller: _castScroll,
                              scrollDirection: Axis.horizontal,
                              clipBehavior: Clip.none,
                              itemCount: cast.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 18),
                              itemBuilder: (_, i) => SizedBox(
                                width: personWidth,
                                child: _photo(
                                  cast[i],
                                  node: i == 0
                                      ? _sectionNodes.putIfAbsent(
                                          'cast',
                                          FocusNode.new,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],
                        if (franchise) ...[
                          _heading(data!.franchiseName ?? 'Franchise'),
                          SizedBox(
                            key: _franchiseKey,
                            height: 260,
                            child: ListView.separated(
                              controller: _franchiseScroll,
                              scrollDirection: Axis.horizontal,
                              itemCount: data.franchise.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 18),
                              itemBuilder: (_, i) => SizedBox(
                                width: 170,
                                child: widget.titleBuilder(
                                  data.franchise[i],
                                  i == 0
                                      ? _sectionNodes.putIfAbsent(
                                          'franchise',
                                          FocusNode.new,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],
                        if (!compact && hasStudio && watch)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: studios),
                              const SizedBox(width: 20),
                              Expanded(child: _watch(data)),
                            ],
                          )
                        else ...[
                          if (hasStudio) studios,
                          if (hasStudio && watch) const SizedBox(height: 20),
                          if (watch) _watch(data),
                        ],
                        const SizedBox(height: 24),
                        const TmdbAttribution(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ExploreHero extends StatefulWidget {
  const _ExploreHero({
    required this.item,
    required this.compact,
    required this.gutter,
  });
  final StremioMeta item;
  final bool compact;
  final double gutter;
  @override
  State<_ExploreHero> createState() => _ExploreHeroState();
}

class _ExploreHeroState extends State<_ExploreHero>
    with MetadataPresentationMixin<_ExploreHero> {
  @override
  StremioMeta get originalMetadata => widget.item;
  @override
  Widget build(BuildContext context) {
    final item = heroPresentation;
    return SizedBox(
      height: widget.compact ? 300 : 350,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item?.background != null)
            _ExploreImage(
              url: item!.background,
              fit: BoxFit.cover,
              width: 1400,
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xF20C1420), Color(0x330C1420)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Color(0xFF0C1420)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: IconButton.filledTonal(
              tooltip: 'Back',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          Positioned(
            left: widget.gutter,
            right: widget.gutter,
            bottom: 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'E X P L O R E',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 14),
                if (item?.logo != null)
                  SizedBox(
                    width: widget.compact ? 240 : 400,
                    height: 85,
                    child: _ExploreImage(
                      url: item!.logo,
                      fit: BoxFit.contain,
                      fallback: Text(
                        item.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    item?.name ?? widget.item.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.compact ? 28 : 38,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  [
                    if (item?.year?.isNotEmpty == true) item!.year!,
                    ...?item?.genres?.take(2),
                  ].join(' · '),
                  style: const TextStyle(color: Colors.white70),
                ),
                if (!widget.compact) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Discover the people and stories behind the title.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreImage extends StatelessWidget {
  const _ExploreImage({
    required this.url,
    this.fit = BoxFit.cover,
    this.icon,
    this.fallback,
    this.width = 342,
  });
  final String? url;
  final BoxFit fit;
  final IconData? icon;
  final Widget? fallback;
  final int width;
  @override
  Widget build(BuildContext context) {
    final empty =
        fallback ??
        ColoredBox(
          color: const Color(0xFF1A2431),
          child: Center(child: Icon(icon, color: Colors.white30, size: 44)),
        );
    if (url?.isNotEmpty != true) return empty;
    return CachedNetworkImage(
      imageUrl: url!,
      fit: fit,
      memCacheWidth: width,
      cacheManager: DebrifyImageCache.manager,
      placeholder: (_, _) => empty,
      errorWidget: (_, _, _) => empty,
    );
  }
}

class _ExploreTile extends StatefulWidget {
  const _ExploreTile({required this.child, this.onTap, this.node});
  final Widget child;
  final VoidCallback? onTap;
  final FocusNode? node;
  @override
  State<_ExploreTile> createState() => _ExploreTileState();
}

class _ExploreTileState extends State<_ExploreTile> {
  bool _focused = false, _hovered = false;
  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.node,
    onFocusChange: (v) {
      setState(() => _focused = v);
      if (v) {
        Scrollable.ensureVisible(
          context,
          alignment: .3,
          duration: const Duration(milliseconds: 220),
        );
      }
    },
    onKeyEvent: (_, e) {
      if (widget.onTap != null &&
          e is KeyDownEvent &&
          isActivateOrSpaceKey(e.logicalKey)) {
        widget.onTap!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Semantics(
      button: widget.onTap != null,
      child: MouseRegion(
        cursor: widget.onTap != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: ParallaxFocus(
          focused: _focused || _hovered,
          radius: BorderRadius.circular(14),
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: _focused || _hovered ? .1 : .035,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: .09)),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    ),
  );
}
