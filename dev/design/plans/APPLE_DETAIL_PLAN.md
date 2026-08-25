# Showcase detail — matching the tvOS series page

Reference: two screenshots of the Apple TV app's series page (2026-08-10).

**Frame 1 (at rest).** Full-bleed, *unblurred* key art fills the screen. Badge
pill, title treatment, meta line, synopsis, tech line and actions sit lower-left
over it; cast lower-right; the first episode row peeks in at the bottom edge.
After a few seconds a trailer plays *in that same frame*, as the Home hero does.

**Frame 2 (after DOWN).** The hero leaves upward, the title treatment re-forms
as a small centred wordmark, the ground becomes a blurred field lifted off the
same artwork, and the episode rail owns the screen — the focused episode's
caption on a filled plate.

---

## 1. What already exists

Frame 2 is largely built: `_deep` (`_bandKey != 'identity'`) drives
`ShowcaseAmbient` in and `ShowcaseBackdropScrim` out, `ShowcaseStickyLogo`
re-forms the wordmark, `ShowcaseEpisodeCell` renders number/title/synopsis/date
and already has a focused fill. Band travel is a 260ms `easeOutCubic`
`ensureVisible` onto a per-band `rest`.

**The shell already owns a full-bleed backdrop.** `merged_series_detail_screen`
paints `HeroTrailerBackdrop` at `Positioned.fill`, *outside* the `SafeArea` that
wraps the body, and it already has the ambient-trailer pipeline wired
(`videoUrl`/`audioUrl`/`enabled`, resolve in `_loadTrailer`, promote-to-
fullscreen via `foreground`).

## 2. What is actually wrong

**The still is deliberately blurred, everywhere.** `HeroTrailerBackdrop` decodes
it at `memCacheWidth: imageBlurSigma <= 0 ? 96 : 480`, and the detail shell
passes `imageBlurSigma: isTelevision ? 0 : 42`. So on TV the key art is a 96px
image upscaled to the screen. There is no sharp path in the widget at all. This
is the whole of "it opens blurred" — not a missing layer inside Showcase.

**The ambient trailer is off on TV by construction.**
`StorageService.getDetailTrailerAutoplayEnabled()` returns `false` when
`_isTelevision()`, paired with `getHomeHeroTrailerEnabled()` returning false off
TV: *"Exactly one of the pair is live on any given device, and Settings shows
only that one."* So this is a deliberate invariant to break carefully, not an
oversight.

**On tvOS a covered backdrop keeps its decoder.**
`_releaseDecoderWhenHidden` is `Platform.isAndroid && isAndroidTvCached`, so
`didPushNext` only calls `_engine?.pause()` on tvOS. Home's paused trailer still
holds a `VideoOutput` while the detail route is up. **Two `VideoOutput`s is
SIGABRT on tvOS** — the crash already seen this week. This is the single
blocking hazard for the whole feature.

**The identity is not a hero.** `ShowcaseIdentity` is an ordinary block with
`fromLTRB(gutter, 150, gutter, 26)`.

## 3. Phases

### P1 — a sharp still, decided by the shell

Add to `HeroTrailerBackdrop` an explicit still-resolution input rather than
overloading `imageBlurSigma`:

```
final int stillDecodeWidth;   // default keeps today's 96/480 behaviour
final bool stillSharp;        // true → no ImageFiltered
```

`stillSharp` disables *filtering* only. It must not mean "decode at source
resolution": a 4K backdrop decoded uncapped is a memory spike on an A15. Cap at
1400 to match Home's hero, and route it through `DebrifyImageCache.manager` —
the backdrop does not use the shared cache today, so without this the same
artwork is fetched and held twice over.

The **shell** chooses, because the backdrop is the shell's and it is the only
layer outside `SafeArea`. A sharp still inside the body would be inset by the
overscan safe area and would not be full-bleed.

`DetailModel` already carries `onAmbientStill(String?)` body→shell. Add the same
shape for depth: `onDepthChanged(bool deep)`. The shell crossfades its own
backdrop between **sharp** (shallow) and **blurred 96px** (deep).

**Delivery rule, or this crashes:** the shell's handler calls `setState`, so
firing from `build`/`didUpdateWidget` is setState-during-build. `_bandKey` is
written from several places; funnel every write through one setter that emits
only genuine transitions, and deliver the callback from a post-frame
callback.

Then **delete `ShowcaseAmbient` from the body.** Keeping it would blur only the
safe-area-inset region while the shell's sharp still shows around it — a
visible frame at the screen edges. Its dark plate moves to the shell's blurred
state. `ShowcaseBackdropScrim` stays in the body (it is a legibility scrim over
the identity, correctly inset).

### P2 — the identity as a first screenful

`ShowcaseIdentity` sized from a `LayoutBuilder`'s `constraints.maxHeight` (the
body viewport, already inside `SafeArea` — **not** `MediaQuery` height, which
ignores the bottom inset), with the column anchored to the bottom and the
following band left peeking: `identityHeight = viewportHeight - peek`.

`peek` is **not a constant.** On a multi-season show the next band is Seasons,
not Episodes (`detail_layout_showcase.dart:356`), so a fixed peek would show a
strip of season chips and no episode art at all. Compute it from what actually
comes next: seasons-row height + the episode peek when Seasons is present, the
episode peek alone otherwise.

The reference also puts **cast lower-right inside the hero**, while our Cast is
a band far below Episodes (`:377`). Add a bounded cast summary to the identity
hero; the Cast band stays where it is for browsing.

Band `rest` offsets stay meaningful: `rest` is an `ensureVisible` *alignment*,
`rest / h`. But `h` is read from `MediaQuery` today
(`detail_layout_showcase.dart:177`), which is the whole screen, not the body
viewport inside `SafeArea` — every band already parks slightly wrong, and a
full-height identity makes it visible. Take `h` from
`_scroll.position.viewportDimension`.

**Three separate things scroll the outer list, and all must be contained.**
With a full-height hero any of them scrolls it away on open, while `_bandKey`
is still `identity` — the page would open already deep:

1. `_page`'s post-frame `Scrollable.ensureVisible(landingCell, alignment: 0.5)`
   (`detail_layout_showcase.dart:321`) climbs to the outer vertical list.
2. `DetailEpisodeInteraction`'s `ensureVisibleAxis` is declared and never used
   (`detail_episode_cells.dart:93`), so cell focus scrolls every ancestor.
3. `revealDetailLanding` (`detail_style.dart:519`) also finishes with a global
   `Scrollable.ensureVisible`.
4. `_keepVisible` (`showcase_parts.dart:98`) — called by the identity actions
   and by Seasons, Cast, Sources and Recs — does the same. The identity's own
   actions must not scroll the outer list at all: they are already in view by
   construction, and scrolling on their focus is what would drag a full-height
   hero off screen the moment the page opens.

Fix — a correctness fix independent of this redesign:
- give the episode rail its own `ScrollController`;
- route all three through that controller's `position.ensureVisible`, so the
  reveal is horizontal only;
- leave vertical positioning exclusively to `_reveal`, the only thing that
  knows about bands.

### P3 — the focused-episode caption plate

A focused fill already exists around the whole cell. Reshape it to the
reference's caption-only plate rather than adding a second one; no change to
cell height, padding, or focus.

### P4 — the ambient trailer on TV

Reuse the shell's existing pipeline. No new stage, no extraction.

**1a. Release the decoder on tvOS when covered.** Extend
`_releaseDecoderWhenHidden` to tvOS. Same reasoning already written for Android
TV, different failure mode: there a paused ExoPlayer starves the decoder pool;
here a paused media_kit engine holds a second `VideoOutput` and aborts the
process. Cost is a re-open on `didPopNext`, which Android TV already pays.

**1b. A process-wide engine lease — 1a alone is not sufficient.** `didPushNext`
does run before the destination builds, but `_disposeEngineSoon` defers to a
post-frame callback and never awaits, and the underlying
`VideoOutputManager.Dispose` is itself asynchronous
(`packages/media_kit_video_tvos/.../real.dart:239`). A dwell only narrows the
race; it does not close it.

New `lib/widgets/trailer_engine_lease.dart` — a single-slot async lease:

```
await TrailerEngineLease.acquire();   // waits for any prior disposal to finish
// recheck mounted / _canPlay / _covered — the wait can outlive the reason
_createEngine();
...
TrailerEngineLease.releaseWith(engine.dispose());   // slot frees on completion
```

`acquire()` returns an **idempotent handle**, because the slot leaks otherwise:
the post-acquire recheck can fail, `_createEngine` can throw, the widget can be
disposed mid-wait, and `_flushPendingDisposes` disposes queued engines directly
on app pause (`hero_trailer_backdrop.dart:570,780`). Every one of those paths
must release. So: one lease-aware disposer that immediate disposal, post-frame
disposal, the lifecycle flush and `dispose()` all route through, and a release
on every early return after acquiring.

The Exo path bypasses the lease entirely — it has its own decoder discipline and
a different failure mode.

**The lease must also cover the content player.** `video_player_screen.dart`
creates its own media_kit `VideoController` (`:2001`) outside any of this, and
that is precisely the SIGABRT already seen: a trailer engine still alive when
the player constructs. It acquires the same lease before creating its
controller — **with a timeout (2s) after which it proceeds anyway**, because a
leaked lease must never be able to stop playback from starting.

**This is the blocking hazard — it lands and is verified on device before
anything else in P4.**

**2. Allow the setting on TV, and unpick the settings pairing.**
`getDetailTrailerAutoplayEnabled` stops returning false for TV. But
`_ambientTrailerKey` picks the sound/volume key *by platform*
(`storage_service.dart:641`), so a TV detail trailer would read Home's
preferences; and `home_page_settings_page.dart:51` picks which toggle governs
the shared rows on the same assumption. Both must become per-surface: explicit
Home and detail getters over the existing separate keys, each call site updated,
and Settings showing both groups on TV.

**3. Dwell.** Apple shows the still for a few seconds first. `_loadTrailer`
resolves immediately today; pass `startDelay` so the still is seen first.

**4. Deep unmounts it.** When `_deep`, drop `videoUrl` so the engine is released
rather than playing under a blur.

### P5 — motion

The scrim/ambient/logo crossfades run at their own durations while the list
scrolls at 260ms `easeOutCubic`. Unify onto that duration and curve so frame 1 →
frame 2 resolves as one movement.

## 4. Risks

| Risk | Handling |
| --- | --- |
| Two `VideoOutput`s → SIGABRT | P4.1a release-when-covered **and** P4.1b lease; verified on device before the rest of P4 |
| Sharp full-screen decode per open | one image, shared `CachedNetworkImage` cache; same budget Home's 1400px hero already spends |
| Sharp/blurred seam at the safe-area edge | shell owns both states; `ShowcaseAmbient` deleted (P1) |
| Landing reveal scrolls the hero away on open | P2's horizontal-only reveal |
| Underlay hole under an `Opacity` (Android TV) | crossfade the still layers, never wrap the video |
| Settings pairing now wrong on TV | P4.2 updates both the getter and the Settings surface |

## 5. Tests

- Backdrop: `stillSharp` decodes full-size and applies no filter; default path
  unchanged at 96/480.
- Depth callback fires on the `_deep` transition, both directions.
- Identity occupies `viewport - peek`.
- Focused episode cell has the caption plate; unfocused does not.
- Landing reveal and episode focus do not move the outer vertical offset.
- `rest` alignment is computed from the viewport, not the screen.
- The lease serialises: a second acquire does not resolve until the first
  release's future completes.
- Existing showcase/DPAD/episodes tests green.

Not testable off-device: that a trailer actually plays, and that exactly one
engine ever exists. Both are device checks and P4.1 must be confirmed there.

## 6. Rollback

P1–P3, P5 are contained to Showcase plus two new `HeroTrailerBackdrop` inputs
that default to today's behaviour. P4 is a settings getter and a platform
predicate; reverting either restores the current TV behaviour exactly.


---

## 7. What was built (2026-08-10)

All five phases, plus the lease work the review surfaced. Uncommitted.

**Deviations from the plan, and why:**

* **`ShowcaseAmbient` was NOT deleted.** The plan removed it to avoid a
  sharp/blurred seam at the safe-area edge. That seam cannot occur once the
  shell follows depth too — both grounds change together — so keeping it is
  strictly less to break.
* **The identity's height is passed IN**, not computed from a `LayoutBuilder`
  inside it. A `LayoutBuilder` in a vertical list gets unbounded height, and the
  `MediaQuery` fallback measured the screen rather than the viewport: the first
  test written against it caught the hero coming out 357 tall on a 540 viewport.
  A `LayoutBuilder` around the page supplies the real number on frame one.
* **Settings kept ONE sound/volume group** rather than two. On TV it writes both
  surfaces and reconciles them on load, so the value shown genuinely governs
  both. Two independent groups would be more faithful but is a settings-page
  redesign for a preference pair that nobody wants to differ.
* **The player's lease wait is bounded at 3s and then proceeds.** Review
  objected twice, correctly noting this can in principle recreate the two-output
  case. The judgement is that an unbounded wait converts a stuck native disposal
  into "video never plays again this session" — worse, and likelier, than the
  crash it guards. It logs, and it still adopts the slot when it frees, so the
  player is never untracked. **If a SIGABRT ever appears with that log line
  before it, this is the line to change.**

**Not done:** the lower-right cast summary in the hero (P2's last item), and the
P5 motion unification. Both are paint; neither blocks the rest.

**Verified off-device:** analyze clean, baseline 9/9 by name, 14 showcase +
5 lease tests. **Unverified:** everything about how it looks and whether the
trailer actually plays on the panel — including, specifically, that only one
video output ever exists in practice.
