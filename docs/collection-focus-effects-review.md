# Collection focus effects review — 2026-09-07

Scope: support imported collection glow settings and folder focus videos across
Home layouts. Leave the work uncommitted.

## Implemented behavior

- Collection `focusGlowEnabled` defaults to true, follows Nuvio's row-level
  setting, and preserves explicit false through import, copies and export.
  The focused/hovered tile gets an artwork-derived halo; the theme's ordinary
  focus cursor remains independent.
- Folder `focusVideoUrl` accepts HTTP(S) clips. `focusVideoEnabled` defaults to
  true, with explicit false honored. Video loops muted from frame zero after
  350 ms of focus/hover. The cover remains below the loading video; failures
  fall back to a configured focus GIF, otherwise the cover.
- Classic/shared stage cards and Spotlight carry both settings. Spotlight
  collection previews also follow desktop keyboard focus; IPTV keeps its
  existing desktop hover-only preview policy.
- The most recently activated collection preview owns ambient playback.
  Releasing a hover restores a still-focused tile. Other ambient trailers stop
  during the preview. Decoder handoff waits for native release and a pending
  open, supplementing the existing media_kit video-output lease for Exo.
- Route changes, app backgrounding, content launch and reduced-motion settings
  stop previews. Android TV uses a 480px texture for transformed/clipped tiles;
  full hero trailers retain their existing underlay preference.

## Review passes

### 1. Schema, persistence and playback lifecycle

Checked the Nuvio collection model and glow implementation, collection parsing,
copy paths, row conversion, storage, backup and inventory serialization. Confirmed
that `heroVideoUrl` describes a different feature (the opened folder's hero).
Added tests for video eligibility, defaults, explicit disable, persistence,
dwell cancellation, first-frame reveal, muted looping, failure/watchdog fallback,
route coverage, reduced motion and takeover of the Home trailer.

Existing collection/trailer regression selection: 63 tests passed. Initial new
behavior suite: 12 tests passed after correcting asynchronous test cleanup and
frame pumping (test-harness issues, not accepted failures).

### 2. Layout and input-policy review

Traced Classic plus all five shared stage call sites and Spotlight. Extended
existing wiring guards and exercised Spotlight's rendered keyboard-focus path.
Found that applying keyboard previews generically would change IPTV's intentional
hover-only behavior; introduced an opt-in used by collection cards. Added ordered
preview ownership so overlapping keyboard focus and pointer hover cannot leave
multiple collection decoders playing or steal playback on a stale release.
Verified the new fields through actual import, visibility changes, re-import,
backup export and restore. Layout/persistence regression selection: 76 passed.

### 3. Failure, backgrounding and visual review

A new backgrounding test exposed post-frame ownership release that could be
stranded when no frames are produced. Fixed immediate background release and
made focus previews dispose on backgrounding on desktop as well as TV. Added
coverage for engine-construction failure and content-player handoff. Enabled
media_kit error reporting for focus clips so mid-play network/decoder errors
also trigger artwork fallback; other trailer callers keep their prior policy.

Rendered and visually inspected `test/goldens/collection_focus_glow.png` with
real shadow painting enabled. Landscape, square and portrait tiles show a halo
only with focus plus glow enabled, and retain their normal focus ring with glow
disabled. The golden uses fallback accent color and synthetic cover art;
artwork color sampling reuses the existing small-image extractor.

## Final verification

183 tests passed with this selection:

```sh
flutter test --no-pub \
  test/collection_focus_effects_test.dart \
  test/collection_focus_visual_test.dart \
  test/hero_trailer_backdrop_test.dart \
  test/discover_trailer_stage_test.dart \
  test/video_output_lease_test.dart \
  test/home_collections_test.dart \
  test/home_collections_storage_test.dart \
  test/home_collections_regression_test.dart \
  test/home_collections_responsive_test.dart \
  test/collections_stage_regression_test.dart \
  test/collection_catalog_pager_test.dart \
  test/profiles/profile_collection_resource_facade_test.dart \
  test/spotlight_board_test.dart \
  test/spotlight_board_compact_test.dart
```

Targeted `flutter analyze --no-pub --no-fatal-infos` on all changed production
Dart entry points and tests: no errors or warnings; 20 existing informational
notices in the large Search, Spotlight and hero files. `git diff --check`: clean.

No physical Android TV was connected. Decoder lifecycle tests use injected
engines; actual codec compatibility and performance on weak TV hardware have not
been measured. No release, commit or push was performed. Existing unrelated
untracked review files were left alone.

Existing imports need re-importing to recover video URLs or an explicit disabled
glow setting that older versions discarded. Folder hero videos are outside this
focus-tile change.
