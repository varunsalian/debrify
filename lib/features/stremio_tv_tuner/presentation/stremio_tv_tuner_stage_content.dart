import 'package:debrify/features/stremio_tv_tuner/presentation/stremio_tv_tuner_parts.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/stremio_tv_tuner_stage.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

class StremioTvTunerStageContent {
  final StremioTvTunerStageState stageState;
  StremioTvTunerStageContent(this.stageState);
  BuildContext get context => stageState.context;
  StremioTvTunerStage get widget => stageState.widget;

  Widget buildContent(StremioMeta? item, bool isNarrow) {
    final app = AppThemeScope.of(context);
    // Staggered cascade offsets mirror the Home hero: tag first, then title,
    // meta, plot, and the live bar/up-next trailing — a channel surf reads as
    // one composed entrance instead of a hard text swap.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        stageState.cascade(_channelTag(), 0.0, 0.6),
        const SizedBox(height: 16),
        if (item == null)
          _tuningState()
        else if (widget.hideNowPlaying) ...[
          _hiddenState(),
          const SizedBox(height: 20),
          stageState.cascade(_liveBar(), 0.32, 1.0),
        ] else ...[
          stageState.cascade(
            Text(
              item.name,
              maxLines: isNarrow ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: app.core.tx,
                fontSize: isNarrow ? 28 : 44,
                height: 1.05,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                shadows: const [Shadow(blurRadius: 16, color: Colors.black)],
              ),
            ),
            0.08,
            0.72,
          ),
          const SizedBox(height: 12),
          stageState.cascade(_metaRow(item), 0.16, 0.8),
          if (item.description != null &&
              item.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            stageState.cascade(
              StremioTvTunerStageDescription(
                text: item.description!.trim(),
                title: item.name,
                ident: widget.ident,
                interactive: isNarrow,
              ),
              0.24,
              0.9,
            ),
          ],
          const SizedBox(height: 22),
          stageState.cascade(_liveBar(), 0.32, 1.0),
          if (widget.nextPlaying != null) ...[
            const SizedBox(height: 14),
            stageState.cascade(_upNext(), 0.4, 1.0),
          ],
        ],
      ],
    );
  }

  Widget glassPill({required IconData icon, required String label}) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.50),
        borderRadius: app.shape.br(24),
        border: Border.all(
          color: app.onGlass.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: app.onGlass.withValues(alpha: 0.85)),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: app.onGlass.withValues(alpha: 0.85),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _channelTag() {
    final app = AppThemeScope.of(context);
    final channel = widget.channel;
    final catalogLabel = channel.genre != null
        ? '${channel.catalog.name} — ${channel.genre}'
        : channel.catalog.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: widget.ident,
                borderRadius: app.shape.br(10),
              ),
              child: Text(
                'CH ${channel.channelNumber.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: app.core.tx,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: app.core.tx.withValues(alpha: 0.08),
                borderRadius: app.shape.br(8),
                border: Border.all(
                  color: app.core.tx.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: Text(
                channel.addon.displayName.toUpperCase(),
                style: TextStyle(
                  color: app.core.tx.withValues(alpha: 0.50),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StremioTvTunerMarquee(
          text: catalogLabel.toUpperCase(),
          style: TextStyle(
            color: app.core.tx.withValues(alpha: 0.72),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
            shadows: const [Shadow(blurRadius: 12, color: Colors.black)],
          ),
        ),
      ],
    );
  }

  Widget _metaRow(StremioMeta item) {
    final app = AppThemeScope.of(context);
    final bits = <Widget>[];
    void add(Widget w) {
      if (bits.isNotEmpty) bits.add(_dot());
      bits.add(w);
    }

    if (item.year != null && item.year!.isNotEmpty) {
      add(Text(item.year!, style: _metaStyle));
    }
    if (item.imdbRating != null) {
      add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 16, color: app.stremioTv.starAccent),
            const SizedBox(width: 4),
            Text(item.imdbRating!.toStringAsFixed(1), style: _metaStyle),
          ],
        ),
      );
    }
    if (item.genres != null && item.genres!.isNotEmpty) {
      add(
        Flexible(
          child: Text(
            item.genres!.take(3).join(' · '),
            style: _metaStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      );
    }
    if (bits.isEmpty) return const SizedBox.shrink();
    return Row(children: bits);
  }

  TextStyle get _metaStyle => TextStyle(
    color: AppThemeScope.of(context).core.tx,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    shadows: const [Shadow(blurRadius: 12, color: Colors.black)],
  );

  Widget _dot() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        color: AppThemeScope.of(context).core.tx.withValues(alpha: 0.40),
        shape: BoxShape.circle,
      ),
    ),
  );

  Widget _liveBar() {
    final app = AppThemeScope.of(context);
    final np = widget.nowPlaying;
    final progress = widget.displayProgress;
    return Row(
      children: [
        // "Live" indicator uses Home's reserved amber highlight; the progress
        // fill below is white like every Home progress bar (was the channel's
        // blue identity colour for both).
        StremioTvTunerLivePip(color: app.home.highlight),
        const SizedBox(width: 9),
        Text(
          'LIVE',
          style: TextStyle(
            color: app.home.highlight,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.5,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ClipRRect(
            borderRadius: app.shape.br(4),
            child: SizedBox(
              height: 5,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: app.stremioTv.progressTrack,
                      borderRadius: app.shape.br(4),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: app.stremioTv.progressFill,
                        borderRadius: app.shape.br(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          np?.progressText ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            color: app.core.tx.withValues(alpha: 0.65),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _upNext() {
    final app = AppThemeScope.of(context);
    final n = widget.nextPlaying!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: app.stremioTv.surfaceFill,
        borderRadius: app.shape.br(12),
        border: Border.all(color: app.stremioTv.hairline, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'UP NEXT',
            style: TextStyle(
              color: widget.ident.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              n.item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: app.core.tx.withValues(alpha: 0.78),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tuningState() {
    final app = AppThemeScope.of(context);
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(widget.ident),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          widget.loading ? 'Tuning in…' : 'No broadcast on this channel',
          style: TextStyle(
            color: app.core.tx.withValues(alpha: 0.7),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _hiddenState() {
    final app = AppThemeScope.of(context);
    return Row(
      children: [
        Icon(
          Icons.visibility_off_rounded,
          size: 28,
          color: app.core.tx.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'Now playing hidden — tune in to reveal',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: app.core.tx.withValues(alpha: 0.78),
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }
}
