import 'package:debrify/features/sources/application/source_filter_ladder.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_provider_choice.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/play_loader_style.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/filter_ladder.dart';
import 'package:debrify/widgets/debrid_loading_overlay.dart';
import 'package:debrify/widgets/pipeline_loading_overlay.dart';
import 'package:flutter/material.dart';

final class SourceLoadingOverlays {
  const SourceLoadingOverlays._();

  static void applyLadderNote(
    PipelineLoadingOverlay overlay,
    FilterLadder ladder,
    List<Torrent> ordered,
  ) {
    final note = SourceFilterLadder.ladderNote(ladder, ordered);
    if (note != null) overlay.setNote(note);
  }

  /// "S04E01"-style label for bound-source hint messages.
  static String seLabel(int season, int episode) =>
      'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';

  /// Show the Pipeline play loader, wired to this provider. [bound] uses the
  /// short (prepare → start) checklist; otherwise it's the full search flow.
  static PipelineLoadingOverlay showPipeline(
    BuildContext context, {
    required String provider,
    required PlaybackMeta? meta,
    required String title,
    bool bound = false,
    VoidCallback? onCancel,
  }) {
    final sub = (meta != null && meta.season != null && meta.episode != null)
        ? seLabel(meta.season!, meta.episode!)
        : null;
    final app = AppThemeScope.of(context);
    return PipelineLoadingOverlay.show(
      context,
      posterUrl: meta?.posterUrl,
      title: title,
      subtitle: sub,
      providerLabel: SourceProviderChoice.label(provider),
      providerCode: SourceProviderChoice.providerCode(provider),
      providerColor: SourceProviderChoice.providerGradient(provider).first,
      bound: bound,
      hasCacheCheck: provider == 'torbox' || provider == 'premiumize',
      // The loader is a dark cinematic plate on every theme (black Material,
      // black-at-alpha scrims), so its ink is `onGlass`, never page ink.
      // `inkOnFill` is already contrast-scored against the accent it sits on.
      loaderGround: app.stremioTv.loaderGround,
      loaderAccent: app.stremioTv.loaderAccent,
      loaderAccent2: app.stremioTv.loaderAccent2,
      railFar: app.stremioTv.loaderRailFar,
      ink: app.onGlass,
      inkOnFill: app.stremioTv.inkOnFill,
      // Settings → Appearance → Play Loader. Read from the synchronous mirror:
      // a play cannot await a preference, and the mirror's default IS the
      // stored default, so an unwarmed read only ever mis-serves someone who
      // explicitly chose Classic.
      style:
          PlayLoaderStyleController.cached == PlayLoaderStyleController.classic
          ? PlayLoaderStyle.classic
          : PlayLoaderStyle.marquee,
      art: meta?.art,
      onCancel: onCancel,
    );
  }

  /// Immediate feedback while Quick Play resolves preferences, resume data,
  /// and pinned sources before the provider-specific pipeline can begin.
  static PipelineLoadingOverlay showResolvingOverlay(
    BuildContext context, {
    required PlaybackMeta? meta,
    required String title,
    VoidCallback? onCancel,
  }) => showPipeline(
    context,
    provider: 'preparing',
    meta: meta,
    title: title,
    onCancel: onCancel,
  );

  // ── Minimal UI feedback ────────────────────────────────────────────────────

  /// The app's shared cinematic add-loading overlay (not a plain spinner box).
  static DebridLoadingHandle showLoading(
    BuildContext context,
    String provider,
    String name,
  ) {
    switch (provider) {
      case 'debrid':
        return DebridLoadingOverlay.showRealDebrid(context, name);
      case 'torbox':
        return DebridLoadingOverlay.showTorbox(context, name);
      case 'premiumize':
        return DebridLoadingOverlay.showPremiumize(context, name);
      case 'alldebrid':
        return DebridLoadingOverlay.showAllDebrid(context, name);
      case 'pikpak':
        return DebridLoadingOverlay.show(
          context,
          provider: 'PikPak',
          torrentName: name,
          accentColor: const Color(0xFF6366F1),
          icon: Icons.cloud_circle_rounded,
        );
      default:
        return DebridLoadingOverlay.show(
          context,
          provider: SourceProviderChoice.label(provider),
          torrentName: name,
        );
    }
  }

  static void snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }
}
