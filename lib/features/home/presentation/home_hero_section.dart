import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import 'home_media_bindings.dart';
import '../application/home_hero_metadata_policy.dart';
import 'home_hero_swap.dart';
import 'home_hero_preview.dart';

typedef HomeHeroDeps = ({
  HomeMediaBindings Function() media,
  bool Function() mounted,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() stageActive,
  bool Function() stagePublishesShellArt,
  VoidCallback clearFavoriteFocus,
  HomeHeroPreview Function() preview,
  VoidCallback clearLive,
});

/// Focus-rest hero selection, metadata, ambient artwork and tint publication.
class HomeHeroSection {
  HomeHeroSection(this._deps, this._shellArt, this._shellTint);
  final HomeHeroDeps _deps;
  final ValueNotifier<String?> _shellArt;
  final ValueNotifier<Color?> _shellTint;

  // Hero state. Driven by ValueNotifiers so focus-driven hero swaps rebuild
  // only the spotlight, never the whole board (important on low-power TVs).
  final ValueNotifier<StremioMeta?> heroItem = ValueNotifier<StremioMeta?>(
    null,
  );
  final ValueNotifier<StremioMeta?> heroEnriched = ValueNotifier<StremioMeta?>(
    null,
  );

  /// Settle debounce for the hero SWAP itself (260ms): while DPAD focus flies
  /// across cards only the card visuals update; the spotlight (backdrop
  /// decode, logo, meta, tint cascade) follows once focus rests.
  final HomeHeroSwap heroSwap = HomeHeroSwap();

  /// Whether the hero spotlight is live for the current tab/state: TV-only.
  /// Dedicated Search uses in-card previews instead of a separate hero.
  /// Single source of truth for
  /// seeding ([_applySections]), focus tracking ([setHero]) and rendering
  /// ([_buildBoard]) so they can't drift.
  bool get heroActive => _deps.isTelevision() && !_deps.searchMode();

  void setHero(StremioMeta item) {
    _deps.preview().heroPreviewPolicy.focus(item.id);
    // Off-TV / blank search prompt the hero isn't rendered, so don't track focus
    // or fire the per-item backdrop-enrichment /meta fetch behind it.
    if (!heroActive) return;
    // Folders own the stage art too, but never request title metadata or video.
    if (item.type == 'folder') {
      _deps.media().metadata.cancel();
      heroSwap.cancel();
      _deps.preview().clearHeroTrailer();
      _deps.clearLive();
      _deps.clearFavoriteFocus();
      heroEnriched.value = null;
      heroItem.value = item;
      publishAmbientArt(item, null);
      updateHeroTint(item);
      return;
    }
    // A catalog/CW card owns the stage again — drop any Canvas favourites
    // override so its art/identity yield to the hero pipeline.
    _deps.clearFavoriteFocus();
    // A catalog/CW card just took focus (possibly straight from the IPTV
    // favourites row, which has no row in between) — drop any live IPTV feed
    // so the boxed video region falls back to this item's own trailer.
    _deps.clearLive();
    if (heroItem.value?.id == item.id) {
      // Back on the current hero (a vertical move within the column, or an
      // A→B→A jiggle inside the swap debounce): drop any pending swap to a
      // neighbour focus merely passed through — and RE-ARM the trailer when
      // the move away already tore it down and nothing is resolving. Without
      // the re-arm, a quick jiggle left the hero permanently trailer-less
      // (cleared on the first keypress, never rescheduled — "some cards
      // never even show the loading pill"). A trailer that's already playing
      // or resolving is left completely alone.
      heroSwap.cancel();
      if (_deps.preview().heroTrailer.value == null &&
          !_deps.preview().heroTrailerLoading.value) {
        _deps.preview().scheduleHeroTrailer(item);
      }
      return;
    }
    // Instant + cheap on EVERY move: kill any trailer (timer cancels and
    // notifier flips) so the lights-off veils start lifting with the
    // keypress, even though the hero swap itself waits for the rest below.
    _deps.preview().clearHeroTrailer();
    // First hero (board just landed) shows instantly. After that, the swap
    // waits for a short DPAD rest — holding a direction across a row costs
    // only the card focus visuals (ring + scale), never a spotlight rebuild
    // plus a backdrop decode per step. This is the Nuvio/Netflix billboard
    // settle debounce from the approved Concept-5 foundations, and the
    // second half of the "navigation feels heavy" fix (the first was the
    // tint cache publishing synchronously).
    if (heroItem.value == null) {
      applyHero(item);
      return;
    }
    heroSwap.schedule(
      isCurrent: () => _deps.mounted(),
      apply: () => applyHero(item),
    );
  }

  /// The real hero swap — everything downstream of "focus has RESTED here".
  void applyHero(StremioMeta item) {
    heroItem.value = item;
    heroEnriched.value = null;
    publishAmbientArt(item, null);
    enrichHero(item);
    updateHeroTint(item);
    // A NEW title in the spotlight lifts the after-the-feature suppression —
    // fresh context, fresh trailer.
    _deps.preview().heroPreviewPolicy.allowNewHero();
    _deps.preview().scheduleHeroTrailer(item);
  }

  /// The hero id the shell stage's current art belongs to — lets a re-seed of
  /// the SAME title (board reloads: See-All return, Home Rows change,
  /// integrations refresh) keep the enriched backdrop on screen instead of
  /// downgrading to the poster for the ~300ms until enrichment re-lands
  /// (which was a prominent full-screen double-crossfade).
  String? ambientArtItemId;

  /// Publish the focused title's key art to the app shell's glass stage
  /// (TvAmbientArtStage — the blurred backdrop BEHIND the sidebar and this
  /// board's transparent scaffold). Rest-cadence only: called from
  /// [applyHero] (260ms settle) and the enrichment landing, never per
  /// keypress. TV Home board only; other modes leave the shell alone.
  void publishAmbientArt(StremioMeta? item, StremioMeta? enriched) {
    if (!_deps.preview().heroTrailerActive) return;
    // Layouts whose own ground is INK (Atrium's panel, Deck's and Tonight's
    // fields, Mosaic's veiled wash) must not light the shell: the shell art
    // only shows in the 64px strip behind the ghost rail, so a bright blurred
    // sliver would butt straight into the board's flat ground and read as a
    // seam. Publishing null leaves the shell on its flat page ink, which is
    // exactly what those boards continue.
    if (_deps.stageActive() && !_deps.stagePublishesShellArt()) {
      ambientArtItemId = null;
      if (_shellArt.value != null) {
        _shellArt.value = null;
      }
      return;
    }
    final update = homeHeroAmbientArtUpdate(
      item: item,
      enriched: enriched,
      publishedItemId: ambientArtItemId,
      publishedArt: _shellArt.value,
    );
    if (update == null) return;
    ambientArtItemId = update.itemId;
    _shellArt.value = update.art;
  }

  // ── Dynamic per-title tint ────────────────────────────────────────────────
  // The hero scrim takes on the focused title's dominant poster color, so the
  // screen shifts mood as you browse. Extraction is debounced (only after
  // focus SETTLES — never per card while flying across a row), cached per
  // title, and decodes a 32px thumbnail — negligible on the TV chip.
  final ValueNotifier<Color?> heroTint = ValueNotifier<Color?>(null);

  void updateHeroTint(StremioMeta item) => _deps.media().tint.load(
    item,
    isCurrent: () => _deps.mounted(),
    publish: (color) {
      heroTint.value = color;
      publishHeroTintToShell(color);
    },
  );

  /// Relay the settled tint to the app shell — the sidebar's glass blends it
  /// in and the shell's art stage tints its washes with it. Rest-cadence and
  /// CONSTANT across trailer start/stop, so there's no colour flooding in or
  /// out at playback edges (the old complaint); the room simply wears the
  /// focused film's hue while browsing. TV Home board only.
  void publishHeroTintToShell(Color? color) {
    if (!_deps.preview().heroTrailerActive) return;
    // The tint exists to make the sidebar read as glass over the SHELL ART.
    // Layouts that publish no art (ink grounds — see [publishAmbientArt])
    // would just get a coloured rail floating on flat ink, so they stay
    // neutral.
    _shellTint.value = (_deps.stageActive() && !_deps.stagePublishesShellArt())
        ? null
        : color;
  }

  /// Debounced backdrop/description enrichment. Catalog list items usually
  /// omit `background`/`description` (they come from the /meta endpoint), so
  /// fetch them lazily — cached in [StremioService], and guarded against the
  /// focus moving on (req id) so a slow fetch never clobbers a newer hero.
  Future<void> enrichHero(StremioMeta item) => _deps.media().metadata.load(
    item,
    isCurrent: () => _deps.mounted(),
    onResolved: (details) {
      heroEnriched.value = details;
      // Publish after enrichment so shell listeners see the accepted value.
      publishAmbientArt(item, heroEnriched.value);
    },
  );
}
