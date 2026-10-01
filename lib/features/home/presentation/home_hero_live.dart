import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import 'home_hero_preview.dart';
import 'home_hero_section.dart';
import 'home_media_bindings.dart';

typedef HomeHeroLiveDeps = ({
  HomeMediaBindings Function() media,
  bool Function() mounted,
});

/// Live-channel hero preview and restoration of the catalog's ambient artwork.
class HomeHeroLive {
  HomeHeroLive(
    this._deps,
    this._heroSection,
    this._heroPreview,
    this._shellArt,
    this._shellTint,
  );
  final HomeHeroLiveDeps _deps;
  final HomeHeroSection _heroSection;
  final HomeHeroPreview _heroPreview;
  final ValueNotifier<String?> _shellArt;
  final ValueNotifier<Color?> _shellTint;

  // Live IPTV favourite hero preview: when DPAD focus rests on an "IPTV" row
  // card, its stream plays in the SAME boxed video region as the catalog
  // trailer above — reusing HeroTrailerBackdrop's `live: true` mode, exactly
  // like the IPTV page's own inline channel preview
  // (IptvResultsView._buildPreviewStage). Painted as a layer above
  // [HomeHeroTrailerLayer] so the two never need to swap types; whichever one
  // actually has a URL to show wins (see [setHeroLiveIptv]).
  final ValueNotifier<String?> heroLiveUrl = ValueNotifier<String?>(null);

  /// Set the INSTANT an IPTV favourite gains focus — well before its stream
  /// (if a Stremio-addon channel) finishes resolving. [_HeroLiveLayer] uses
  /// this to occlude the region with the channel's OWN art immediately, so
  /// the previously-focused catalog title's Cinemeta poster never shows
  /// through the resolve/buffer gap underneath.
  final ValueNotifier<IptvChannel?> heroLiveChannel =
      ValueNotifier<IptvChannel?>(null);

  /// Boolean mirror of [heroLiveChannel] for [HomeHeroSpotlight.liveTakeover] —
  /// the spotlight fades its (now-stale) colour field and identity text on
  /// this, and has no other reason to know the IPTV-specific channel type.
  final ValueNotifier<bool> heroLiveTakeover = ValueNotifier<bool>(false);

  /// DPAD focus rested on an IPTV favourite card — retune the boxed hero video
  /// region to that channel's live stream. A plain M3U/Xtream favourite's URL
  /// is already playable; a Stremio-addon favourite resolves candidates first
  /// (same async ladder [IptvResultsView] uses for its own inline preview),
  /// guarded by the live-preview owner so a fast DPAD move cannot land a stale
  /// resolve on top of whatever channel focus has since moved to.
  void setHeroLiveIptv(IptvChannel channel) {
    if (!_heroPreview.heroTrailerActive) return;
    if (heroLiveChannel.value?.url == channel.url) return;
    heroLiveChannel.value = channel;
    if (!heroLiveTakeover.value) heroLiveTakeover.value = true;
    _deps.media().live.load(
      channel.url,
      isCurrent: () => _deps.mounted(),
      prepare: () {
        // A live feed pre-empts whatever catalog trailer is mid-flight/playing —
        // instant teardown, same as any other hero change.
        _heroPreview.clearHeroTrailer();
        heroLiveUrl.value = null;
        // The shell's glass-stage backdrop and sidebar tint are ALSO the stale
        // catalog title's art (published by [_heroSection.publishAmbientArt]/
        // [_heroSection.publishHeroTintToShell], neither of which this focus path runs) —
        // blank them too rather than leaving that art behind everything,
        // including the sidebar, while an unrelated channel plays.
        _shellArt.value = null;
        _shellTint.value = null;
      },
      publish: (url) => heroLiveUrl.value = url,
    );
  }

  /// DPAD focus left the IPTV favourites row (another favourites row, or a
  /// catalog/CW card) — drop the live feed so the boxed region falls back to
  /// whatever catalog trailer [_heroSection.heroItem] owns.
  void clearHeroLiveIptv() {
    _deps.media().live.invalidateRequest();
    final wasLive = heroLiveChannel.value != null;
    if (wasLive) heroLiveChannel.value = null;
    if (heroLiveTakeover.value) heroLiveTakeover.value = false;
    _deps.media().live.clearCandidates();
    if (heroLiveUrl.value != null) heroLiveUrl.value = null;
    // The unmounting live backdrop can never report playing:false (its
    // dispose doesn't notify), and when the trailer path declines to re-arm
    // (trailers off / suppressed) nothing else resets these — a stuck
    // showing=true kept canvas theater re-firing over a static stage and
    // held the shell's lights off.
    if (wasLive) {
      if (_heroPreview.heroTrailerShowing.value) {
        _heroPreview.heroTrailerShowing.value = false;
      }
      if (_heroPreview.heroTrailerLoading.value) {
        _heroPreview.heroTrailerLoading.value = false;
      }
    }
    // Restore the shell's glass-stage backdrop/tint for whatever catalog
    // title the hero already holds. Needed even when DPAD focus returns to
    // the SAME card it was on before IPTV took over: _heroSection.setHero's "back on the
    // current hero" branch doesn't re-run _heroSection.publishAmbientArt/
    // _heroSection.publishHeroTintToShell (no item change to react to), so without this
    // the shell would stay on the blank/neutral state setHeroLiveIptv left
    // it in.
    if (wasLive && _heroPreview.heroTrailerActive) {
      _heroSection.publishAmbientArt(
        _heroSection.heroItem.value,
        _heroSection.heroEnriched.value,
      );
      // Through the GATE, not straight at the bridge: the ink-ground layouts
      // publish no shell tint, and restoring one here would leave a coloured
      // sidebar sitting on a flat board until something else cleared it.
      _heroSection.publishHeroTintToShell(_heroSection.heroTint.value);
    }
  }

  /// The boxed hero region's live IPTV feed genuinely failed (refused to
  /// open, errored, or stalled past the first-frame timeout) — step down its
  /// candidate ladder, mirroring the IPTV page's own inline preview
  /// (IptvResultsView._onPreviewPlaybackFailed). No-op for a plain M3U/Xtream
  /// favourite (single URL, no ladder) or once every candidate is exhausted.
  void onHeroLivePlaybackFailed() {
    _deps.media().live.playbackFailed(
      currentUrl: heroLiveUrl.value,
      channelKey: () => heroLiveChannel.value?.url,
      publish: (url) => heroLiveUrl.value = url,
    );
  }
}
