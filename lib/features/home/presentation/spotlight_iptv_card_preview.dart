import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/iptv_playlist.dart';
import '../../../widgets/hero_trailer_backdrop.dart';
import '../application/home_spotlight_live_dependencies.dart';
import '../application/home_spotlight_live_preview.dart';

/// Live IPTV preview drawn directly inside the active Spotlight card.
///
/// The Spotlight board mounts this only for the pointer-hovered card on desktop
/// or the DPAD-focused card on TV, so a shelf never opens more than one stream
/// while the user browses. Stremio-backed channels retain the same candidate
/// ladder as the full IPTV preview stage; plain M3U/Xtream channels open their
/// declared URL directly. Its audio follows the user's Home ambient-audio
/// setting, so the channel is audible without overriding an intentional mute.
class SpotlightIptvCardPreview extends ConsumerStatefulWidget {
  final IptvChannel channel;
  final double ambientVolume;

  const SpotlightIptvCardPreview({
    super.key,
    required this.channel,
    required this.ambientVolume,
  });

  @override
  ConsumerState<SpotlightIptvCardPreview> createState() =>
      _SpotlightIptvCardPreviewState();
}

class _SpotlightIptvCardPreviewState
    extends ConsumerState<SpotlightIptvCardPreview> {
  String? _streamUrl;
  late final ProviderSubscription<HomeSpotlightLivePreview> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = ref.listenManual(
      homeSpotlightLivePreviewProvider(createHomeSpotlightLiveSession()),
      (previous, next) {},
    );
    _resolve(notify: false);
  }

  @override
  void didUpdateWidget(SpotlightIptvCardPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A shelf can reorder/reload while its active card's State is retained.
    // Never carry the previous channel's stream (or a late candidate resolve)
    // into the card that inherited that State slot.
    if (!identical(oldWidget.channel, widget.channel)) _resolve();
  }

  @override
  void dispose() {
    _subscription.read().dispose();
    _subscription.close();
    super.dispose();
  }

  void _resolve({bool notify = true}) => _subscription.read().resolve(
    channelKey: widget.channel.url,
    isSeries: widget.channel.contentType == 'series',
    isCurrent: () => mounted,
    publish: (url, notify) => _setStreamUrl(url, notify: notify),
    notify: notify,
  );

  void _setStreamUrl(String? value, {bool notify = true}) {
    if (_streamUrl == value) return;
    if (!notify) {
      _streamUrl = value;
      return;
    }
    setState(() => _streamUrl = value);
  }

  void _onPlaybackFailed() => _subscription.read().playbackFailed(
    currentUrl: _streamUrl,
    channelKey: widget.channel.url,
    publish: _setStreamUrl,
  );

  @override
  Widget build(BuildContext context) {
    final url = _streamUrl;
    if (url == null) return const SizedBox.expand();
    final channel = widget.channel;
    return RepaintBoundary(
      child: HeroTrailerBackdrop(
        // A candidate-ladder step needs a fresh player; retaining a dead
        // engine would leave the logo visible forever after its replacement
        // URL was selected.
        key: ValueKey('spotlight-iptv-card-${channel.url}-$url'),
        imageUrl: null,
        videoUrl: url,
        enabled: true,
        live: true,
        httpHeaders: channel.playbackHeaders,
        imageBlurSigma: 0,
        videoBlurSigma: 0,
        // The short dwell filters a pointer sweep / held DPAD move without
        // making a deliberate card preview feel late.
        startDelay: const Duration(milliseconds: 300),
        ambientVolume: widget.ambientVolume,
        onPlaybackFailed: _onPlaybackFailed,
        firstFrameTimeout: _subscription.read().isAddonChannel(channel.url)
            ? const Duration(seconds: 12)
            : null,
      ),
    );
  }
}
