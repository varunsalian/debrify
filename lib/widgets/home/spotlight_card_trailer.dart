import 'package:flutter/material.dart';

import '../../models/metadata_preferences.dart';
import '../../models/stremio_addon.dart';
import '../../services/collection_focus_playback.dart';
import '../../services/imdb_trailer_service.dart';
import '../../services/metadata_preferences_service.dart';
import '../../services/metadata_provider_service.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/stremio_service.dart';
import '../../services/youtube_service.dart';
import '../hero_trailer_backdrop.dart';

/// Mounted only after a focused card's dwell. Shares the ambient decoder lease
/// with the hero and releases it when focus leaves and this widget unmounts.
class SpotlightCardTrailer extends StatefulWidget {
  const SpotlightCardTrailer({
    super.key,
    required this.item,
    required this.volume,
    required this.onPlayingChanged,
  });

  final StremioMeta item;
  final double volume;
  final ValueChanged<bool> onPlayingChanged;

  @override
  State<SpotlightCardTrailer> createState() => _SpotlightCardTrailerState();
}

class _SpotlightCardTrailerState extends State<SpotlightCardTrailer> {
  final _owner = Object();
  final Object? _scope = ProfileRuntime.scope.value;
  YoutubeResolvedStreams? _streams;
  bool _failed = false;

  bool get _current => mounted && ProfileRuntime.scope.value == _scope;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final item = widget.item;
      final prefs = await MetadataPreferencesService.loadForBackground(
        isCurrent: () => _current,
      );
      if (prefs == null || !_current) return;
      final imdb = item.effectiveImdbId;
      final candidates = await MetadataProviderService.instance.trailers(
        item,
        () async {
          if ((item.trailerYtId ?? '').isNotEmpty) return item.trailerYtId;
          if (imdb == null || !_current) return null;
          return (await StremioService.instance.fetchMetaDetails(
            imdbId: imdb,
            type: item.type,
          ))?.trailerYtId;
        },
        preferences: prefs,
      );
      if (!_current) return;
      final youtubeId = candidates.firstOrNull?.key;
      var streams = youtubeId == null
          ? null
          : await YoutubeService.resolveStreams(
              youtubeId,
              maxHeightOverride: 480,
              preferVp9: false,
            );
      if (!_current) return;
      if ((streams == null || !streams.hasPlayable) &&
          imdb != null &&
          (prefs.provider(MetadataCategory.trailers) ==
                  MetadataPreferences.current ||
              prefs.fallback)) {
        streams = await ImdbTrailerService.resolveTrailer(imdb, maxHeight: 480);
      }
      if (!_current || streams == null || !streams.hasPlayable) return;
      if (ModalRoute.of(context)?.isCurrent == false ||
          (WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed))
        return;
      // Notify competing ambient surfaces before mounting this decoder.
      CollectionFocusPlayback.claim(_owner);
      setState(() => _streams = streams);
    } catch (_) {
      // Artwork remains visible when the provider or stream is unavailable.
    }
  }

  @override
  void dispose() {
    CollectionFocusPlayback.release(_owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final streams = _streams;
    if (!_current || _failed || streams == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: HeroTrailerBackdrop(
        imageUrl: null,
        videoUrl: streams.playUrl,
        audioUrl: streams.audioUrl,
        enabled: true,
        focusPreviewOwner: _owner,
        ambientVolume: widget.volume,
        imageBlurSigma: 0,
        videoBlurSigma: 0,
        startDelay: Duration.zero,
        firstFrameTimeout: const Duration(seconds: 12),
        onPlayingChanged: widget.onPlayingChanged,
        onPlaybackFailed: () {
          if (!mounted) return;
          setState(() => _failed = true);
          CollectionFocusPlayback.release(_owner);
          widget.onPlayingChanged(false);
        },
      ),
    );
  }
}
