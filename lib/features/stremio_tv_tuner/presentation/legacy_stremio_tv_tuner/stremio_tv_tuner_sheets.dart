import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_dependencies.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_owners.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_sections.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_widget_view.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StremioTvTunerSheets {
  final StremioTvTunerDependencies _deps;
  StremioTvTunerSheets(this._deps);
  StremioTvTunerWidgetView get widget => _deps.view;
  StremioTvTunerOwners get _owners => _deps.owners;
  StremioTvTunerSections get _sections => _deps.sections();

  // --- Long-press quick actions ------------------------------------------

  Future<void> openActions(StremioTvChannel channel) async {
    final ident = _sections.channels.identFor(channel);
    // Read from THIS context, not the sheet's: the sheet route sits above the
    // surface's theme boundary, so a captured value is what keeps it in step.
    final app = AppThemeScope.of(_deps.context());
    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: _deps.context(),
      backgroundColor: app.stremioTv.sheetBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        Widget tile(
          IconData icon,
          String label,
          VoidCallback onTap, {
          Color? tint,
        }) {
          return ListTile(
            leading: Icon(icon, color: tint ?? app.core.tx.withAlpha(0xB3)),
            title: Text(
              label,
              style: TextStyle(color: app.core.tx, fontWeight: FontWeight.w600),
            ),
            onTap: () {
              Navigator.of(ctx).pop();
              onTap();
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: app.core.tx.withAlpha(0x3D),
                  borderRadius: app.shape.br(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 26,
                      decoration: BoxDecoration(
                        color: ident,
                        borderRadius: app.shape.br(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        channel.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: app.core.tx,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              tile(
                Icons.play_arrow_rounded,
                'Play this channel now',
                () => widget.onPlay(channel),
                tint: ident,
              ),
              if (!widget.hideNowPlaying)
                tile(
                  Icons.info_outline_rounded,
                  'View details',
                  () => widget.onOpenDetail(channel),
                ),
              if (!widget.hideNowPlaying)
                tile(
                  Icons.live_tv_rounded,
                  'Channel guide',
                  () => widget.onShowGuide(channel),
                ),
              tile(
                channel.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                channel.isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                () => widget.onToggleFavorite(channel),
                tint: channel.isFavorite ? app.stremioTv.starAccent : null,
              ),
              if (channel.isLocal && widget.onEditLocal != null)
                tile(
                  Icons.edit_rounded,
                  'Edit local catalog',
                  () => widget.onEditLocal!(channel),
                ),
              if (channel.isLocal && widget.onExportLocal != null)
                tile(
                  Icons.copy_all_rounded,
                  'Copy catalog JSON',
                  () => widget.onExportLocal!(channel),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // --- Channels overview (mobile) ----------------------------------------

  void openChannelList() {
    Timer? sheetTick;
    final app = AppThemeScope.of(_deps.context());
    showModalBottomSheet<void>(
      context: _deps.context(),
      backgroundColor: app.stremioTv.sheetBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.96,
        expand: false,
        builder: (ctx, scrollCtrl) => StatefulBuilder(
          builder: (ctx, setSheet) {
            sheetTick ??= Timer.periodic(const Duration(seconds: 5), (_) {
              if (ctx.mounted) setSheet(() {});
            });
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: app.core.tx.withAlpha(0x3D),
                    borderRadius: app.shape.br(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'All channels',
                      style: TextStyle(
                        color: app.core.tx,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    itemCount: widget.channels.length,
                    itemBuilder: (ctx, i) =>
                        _channelListRow(widget.channels[i], ctx),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ).whenComplete(() => sheetTick?.cancel());
  }

  Widget _channelListRow(StremioTvChannel channel, BuildContext ctx) {
    widget.ensureLoaded(channel);
    final app = AppThemeScope.of(_deps.context());
    final ident = _sections.channels.identFor(channel);
    final np = widget.hideNowPlaying
        ? null
        : _sections.channels.nowPlaying(channel);
    final poster = np?.item.poster;
    final active = channel.id == _owners.activeId.value;
    return Material(
      color: active ? ident.withValues(alpha: 0.16) : Colors.transparent,
      child: InkWell(
        onTap: () {
          final idx = widget.channels.indexWhere((c) => c.id == channel.id);
          Navigator.of(ctx).pop();
          if (idx >= 0 && _owners.pageController.hasClients) {
            _owners.pageController.jumpToPage(idx);
            _sections.channels.setActive(widget.channels[idx]);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 42,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: ident,
                  borderRadius: app.shape.br(6),
                ),
                child: Text(
                  'CH ${channel.channelNumber.toString().padLeft(2, '0')}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: app.core.tx,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: app.shape.brImg(6),
                child: SizedBox(
                  width: 40,
                  height: 60,
                  child: poster != null
                      ? CachedNetworkImage(
                          imageUrl: poster,
                          fit: BoxFit.cover,
                          memCacheWidth: 120,
                          errorWidget: (_, __, ___) =>
                              _listThumbFallback(ident, channel),
                        )
                      : _listThumbFallback(ident, channel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      channel.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: app.core.tx,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.hideNowPlaying
                          ? 'Now playing hidden'
                          : (np?.item.name ??
                                (widget.loadingChannelIds.contains(channel.id)
                                    ? 'Tuning in…'
                                    : 'No broadcast')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: app.core.tx.withValues(alpha: 0.62),
                        fontSize: 12,
                      ),
                    ),
                    if (np != null) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: app.shape.br(2),
                        child: LinearProgressIndicator(
                          value: widget
                              .displayProgress(channel, np.progress)
                              .clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor: app.core.tx.withValues(alpha: 0.14),
                          valueColor: AlwaysStoppedAnimation(ident),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (channel.isFavorite)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: app.stremioTv.starAccent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listThumbFallback(Color ident, StremioTvChannel channel) {
    final app = AppThemeScope.of(_deps.context());
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ident.withValues(alpha: 0.35), app.home.posterPlaceholder],
        ),
      ),
      child: Icon(
        channel.type == 'series' ? Icons.live_tv_rounded : Icons.movie_rounded,
        size: 18,
        color: app.core.tx.withValues(alpha: 0.3),
      ),
    );
  }
}
