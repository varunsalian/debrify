import 'dart:async';

import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/models/resolved_source.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_loading_overlays.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_player_launch.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_provider_choice.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:flutter/material.dart';

final class SourcePlayAction {
  const SourcePlayAction._();

  // ── Post-action branch handlers ────────────────────────────────────────────

  static Future<void> play(
    BuildContext context,
    ResolvedSource r,
    Torrent torrent, {
    required String provider,
    PlaybackMeta? meta,
    List<Torrent>? sources,
    int sourceIndex = 0,
    required AutomaticSourceBindings sourceBindings,
  }) async {
    if (r.playUrl == null || r.playUrl!.isEmpty) {
      SourceLoadingOverlays.snack(context, 'No playable link for this source.');
      return;
    }
    // Refuse a resolved single file that clearly isn't a video (parity with the
    // old screen's MIME check). Scoped to KEYWORD play (meta == null) so this
    // shared path doesn't add a new constraint to catalog board plays. Only
    // fires when we know the real filename; packs are video-filtered upstream.
    if (meta == null &&
        !r.hasPlaylist &&
        r.fileName != null &&
        r.fileName!.isNotEmpty &&
        !FileUtils.isVideoFile(r.fileName!)) {
      SourceLoadingOverlays.snack(
        context,
        'Added to ${SourceProviderChoice.label(provider)}, but the file is not a video.',
      );
      return;
    }
    // For keyword play (no catalog meta) prefer the provider's canonical file
    // name as the title, so the player's resume/Continue-Watching key matches
    // the same item played from the Debrid screen (old-screen parity). Catalog
    // play keeps its clean meta title.
    final playTitle =
        (meta == null &&
            !r.hasPlaylist &&
            r.fileName != null &&
            r.fileName!.isNotEmpty)
        ? r.fileName!
        : torrent.displayTitle;
    await SourcePlayerLaunch.launch(
      context,
      r,
      playTitle,
      provider: provider,
      meta: meta,
      sources: sources ?? [torrent],
      sourceIndex: sourceIndex,

      sourceBindings: sourceBindings,
    );
  }
}
