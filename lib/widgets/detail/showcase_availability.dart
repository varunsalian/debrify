import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/metadata_preferences.dart';
import '../../services/debrify_image_cache.dart';
import '../../services/metadata_details_service.dart';
import '../../services/metadata_explore_service.dart';
import '../../services/tmdb_metadata_repository.dart';
import 'showcase_parts.dart';
import '../../theme/widgets/parallax_focus.dart';

class ShowcaseAvailabilityEntry {
  const ShowcaseAvailabilityEntry(
    this.name, {
    this.logo,
    this.kind,
    this.id,
    this.link,
  });
  final String name;
  final String? logo, kind, link;
  final int? id;
}

class ShowcaseAvailabilityRow {
  const ShowcaseAvailabilityRow(
    this.key,
    this.title,
    this.entries, {
    this.wide = false,
  });
  final String key, title;
  final List<ShowcaseAvailabilityEntry> entries;
  final bool wide;
}

List<ShowcaseAvailabilityRow> showcaseAvailabilityRows(
  MetadataExploreData? data,
  MetadataPreferences? prefs, {
  bool failed = false,
}) {
  if (prefs == null) return [];
  final companies = prefs.features.contains(MetadataFeature.companies);
  final availability = prefs.features.contains(MetadataFeature.availability);
  if (!companies && !availability) return [];
  if (failed) {
    return [
      const ShowcaseAvailabilityRow(
        'availability-retry',
        'Studios & availability',
        [ShowcaseAvailabilityEntry('Could not load. Retry', kind: 'retry')],
        wide: true,
      ),
    ];
  }
  if (data == null) return [];
  final rows = <ShowcaseAvailabilityRow>[];
  if (companies) {
    final entries = <ShowcaseAvailabilityEntry>[
      for (final kind in ['company', 'network'])
        for (final entity in kind == 'company' ? data.companies : data.networks)
          if (MetadataDetailsService.positiveId(entity['id']) != null)
            ShowcaseAvailabilityEntry(
              '${entity['name'] ?? ''}',
              id: MetadataDetailsService.positiveId(entity['id']),
              kind: kind,
              logo: TmdbMetadataRepository.image(
                entity['logo_path'],
                size: 'w185',
              ),
            ),
    ];
    if (entries.isNotEmpty) {
      rows.add(
        ShowcaseAvailabilityRow(
          'studios',
          'Studios & networks',
          entries,
          wide: true,
        ),
      );
    }
  }
  if (availability) {
    var first = true;
    for (final kind in const {
      'flatrate': 'Subscription',
      'free': 'Free',
      'ads': 'With ads',
      'rent': 'Rent',
      'buy': 'Buy',
    }.entries) {
      final entries = <ShowcaseAvailabilityEntry>[
        for (final provider
            in data.providers[kind.key] ?? <Map<String, dynamic>>[])
          if (MetadataDetailsService.text(provider['provider_name']) != null)
            ShowcaseAvailabilityEntry(
              provider['provider_name'] as String,
              logo: TmdbMetadataRepository.image(
                provider['logo_path'],
                size: 'w185',
              ),
            ),
      ];
      if (entries.isEmpty) continue;
      rows.add(
        ShowcaseAvailabilityRow(
          'watch-${kind.key}',
          '${first ? 'Where to watch · ${prefs.region} — ' : ''}${kind.value}',
          entries,
        ),
      );
      first = false;
    }
    final uri = Uri.tryParse(data.providerLink ?? '');
    final valid =
        uri?.scheme == 'https' &&
        const {'www.themoviedb.org', 'themoviedb.org'}.contains(uri?.host);
    rows.add(
      ShowcaseAvailabilityRow(
        'watch-attribution',
        first
            ? 'Where to watch · ${prefs.region}'
            : 'Availability via JustWatch · TMDB',
        [
          ShowcaseAvailabilityEntry(
            first
                ? 'No availability information for this region'
                : valid
                ? 'Check availability on TMDB'
                : 'Availability information',
            link: valid ? uri.toString() : null,
          ),
        ],
        wide: true,
      ),
    );
  }
  return rows;
}

/// Uses the same metrics and ambient canvas as the surrounding Showcase bands.
class ShowcaseAvailabilityBand extends StatelessWidget {
  const ShowcaseAvailabilityBand({
    super.key,
    required this.row,
    required this.nodes,
    required this.accent,
    required this.onRetry,
    this.onStudio,
  });
  final ShowcaseAvailabilityRow row;
  final List<FocusNode> nodes;
  final Color accent;
  final VoidCallback onRetry;
  final ValueChanged<ShowcaseAvailabilityEntry>? onStudio;

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final scale = m.compact ? 1.0 : m.k;
    return Padding(
      padding: EdgeInsets.only(top: 20 * scale, bottom: 12 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: m.gutter),
            child: Text(
              row.title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .85),
                fontSize: m.title,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(height: 14 * scale),
          SizedBox(
            height: (row.wide ? 100 : 148) * scale,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(horizontal: m.gutter),
              itemCount: row.entries.length,
              separatorBuilder: (_, _) => SizedBox(width: 16 * scale),
              itemBuilder: (context, i) => SizedBox(
                width: row.wide
                    ? (m.compact ? m.w * .8 : 290 * scale)
                    : 112 * scale,
                child: _AvailabilityTile(
                  entry: row.entries[i],
                  node: nodes[i],
                  accent: accent,
                  scale: scale,
                  wide: row.wide,
                  onTap: row.entries[i].kind == 'retry'
                      ? onRetry
                      : row.entries[i].kind != null && onStudio != null
                      ? () => onStudio!(row.entries[i])
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityTile extends StatefulWidget {
  const _AvailabilityTile({
    required this.entry,
    required this.node,
    required this.accent,
    required this.scale,
    required this.wide,
    this.onTap,
  });
  final ShowcaseAvailabilityEntry entry;
  final FocusNode node;
  final Color accent;
  final double scale;
  final bool wide;
  final VoidCallback? onTap;
  @override
  State<_AvailabilityTile> createState() => _AvailabilityTileState();
}

class _AvailabilityTileState extends State<_AvailabilityTile> {
  bool _focused = false;
  bool _hovered = false;
  bool get _interactive => widget.onTap != null || widget.entry.link != null;
  Future<void> _activate() async {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    final link = widget.entry.link;
    if (link == null) return;
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the browser.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final entry = widget.entry;
    Widget fallback() => Icon(
      entry.kind == 'company' || entry.kind == 'network'
          ? Icons.business_outlined
          : Icons.live_tv_outlined,
      color: Colors.white54,
      size: 32 * s,
    );
    final logo = SizedBox(
      width: 66 * s,
      height: 66 * s,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12 * s),
        child: entry.logo == null
            ? fallback()
            : CachedNetworkImage(
                imageUrl: entry.logo!,
                cacheManager: DebrifyImageCache.manager,
                memCacheWidth: 185,
                fit: BoxFit.contain,
                placeholder: (_, _) => fallback(),
                errorWidget: (_, _, _) => fallback(),
              ),
      ),
    );
    final label = Text(
      entry.name,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      textAlign: widget.wide ? TextAlign.left : TextAlign.center,
      style: TextStyle(
        color: Colors.white.withValues(alpha: .88),
        fontSize: 12 * s,
        height: 1.25,
      ),
    );
    return Focus(
      focusNode: widget.node,
      onFocusChange: (value) {
        setState(() => _focused = value);
        if (value) {
          final box = context.findRenderObject();
          final rail = Scrollable.maybeOf(context);
          // Showcase owns vertical band positioning; focus reveals only the
          // tile's horizontal rail, never the enclosing detail page.
          if (box is RenderBox &&
              box.attached &&
              rail?.position.axis == Axis.horizontal) {
            rail!.position.ensureVisible(
              box,
              alignment: .5,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          }
        }
      },
      onKeyEvent: (_, event) {
        if (_interactive &&
            event is KeyDownEvent &&
            {
              LogicalKeyboardKey.enter,
              LogicalKeyboardKey.select,
              LogicalKeyboardKey.space,
              LogicalKeyboardKey.gameButtonA,
            }.contains(event.logicalKey)) {
          _activate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        button: _interactive,
        label: entry.name,
        child: MouseRegion(
          cursor: _interactive ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: ParallaxFocus(
            focused: _focused || _hovered,
            radius: BorderRadius.circular(7 * s),
            child: InkWell(
              onTap: _interactive ? _activate : null,
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(7 * s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.all(10 * s),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: _focused || _hovered ? .11 : .05,
                  ),
                  borderRadius: BorderRadius.circular(7 * s),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .09),
                  ),
                ),
                child: widget.wide
                    ? Row(
                        children: [
                          if (entry.kind == 'company' ||
                              entry.kind == 'network') ...[
                            logo,
                            SizedBox(width: 12 * s),
                          ],
                          Expanded(child: label),
                          if (_interactive)
                            Icon(
                              entry.link != null
                                  ? Icons.open_in_new
                                  : Icons.chevron_right,
                              size: 18 * s,
                              color: Colors.white70,
                            ),
                        ],
                      )
                    : Column(
                        children: [
                          logo,
                          SizedBox(height: 10 * s),
                          Flexible(child: label),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
