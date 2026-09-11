# Optional TV motion and Spotlight scroll follow

Base: `077f2e79` (`upstream/webdav-sync`). Worktree: `.worktrees/upstream-motion`.
Branch: `codex/upstream-tv-motion`. Verified 2026-09-11 on Windows using
Flutter 3.44.8 / Dart 3.12.2 at `.tools/flutter-3.44.8`.

## Scope and behavior

This is a selective port of the preference/root propagation ideas from
`b6f844a5` and `8bb08841`, and the Spotlight reveal fix from `b219716f`.
It does not cherry-pick their other motion migrations.

- Adds Appearance > Display > TV motion, with Snappy selected unless explicitly
  changed. Settings search also exposes the picker on TV.
  Existing upstream menu groups, labels, and relative row order are preserved.
  The two following Player rows only receive shifted focus indices for the new
  entry. No settings rearrangement, title/rating controls, or previews are ported.
- Only Spotlight card scroll-follow adopts the new policy. Explicit Smooth is
  260ms; Android TV Snappy stays instantaneous, while tvOS Snappy preserves
  upstream's existing 220ms. Off-TV stays 220ms. Reduced motion is zero.
  These scroll durations retain their literal values under custom theme tempo.
  The existing `easeOutCubic` curve and alignment are unchanged.
- Motion dependencies are captured in the card's build callback. The current
  upstream loading, hero visibility, metadata, preview, focus, and cache logic
  remains intact. The separate return-to-hero animation is unchanged.
- `TvMotionRoot` subscribes above the Navigator and ProfileGate and republishes
  an inherited theme. Selection and profile warmers update already-mounted
  consumers; listeners are removed on disposal.
- `tv_motion_profile` uses `ProfilePreferences`, with the scope captured before
  asynchronous access. Reads/writes are serialized to preserve rapid selection
  order, and stale warm completions cannot overwrite a later choice.
- Reset, activation, and rollback follow the existing profile lifecycle.
  Unset, unrecognized, and unreadable preferences fall back to Snappy.
- The key belongs to `ProfileAppearancePreferences.keys`, so automatic WebDAV
  publication, legacy merge/materialization, replay, and bootstrap exclude it.
  It remains eligible for explicit backups and profile-default copies, matching
  the other appearance keys.

No Collections, hover, shared-wrapper migrations, dependency changes, device
operations, push, or PR creation are included. The prior fork fix was confirmed
on AM9; this upstream port has not been device-certified.

## Verification

Dependencies: pinned SDK `flutter pub get --enforce-lockfile`; lockfile unchanged.

1. With upstream's original Spotlight callback and the preference test harness
   installed, the real DPAD Smooth/intermediate-frame and rapid-repeat tests
   failed; four compatibility tests passed. This is a behavioral failure,
   not the initial missing-import adaptation error.
2. Removing the root subscription caused the profile-switch test to fail: the
   same mounted consumer retained Smooth after the incoming profile warmed
   Snappy. Restoring the subscription passed.
3. Final related regression selection: **163 passed**. Includes nine real
   Spotlight DPAD cases (intermediate frames, curve, repeats/reversal, tvOS,
   off-TV, reduced motion), preference/race/isolation/root-refresh tests,
   picker navigation, actual Appearance-pane entry/return, existing Spotlight
   board and compact behavior, appearance focus-index guards, profile isolation,
   WebDAV hot-state appearance exclusions, and existing theme motion policies.
4. Three unrelated tests failed both with the port and with original upstream
   source restored in this worktree. They were excluded from the final selection:
   - `TV Spotlight settings visual`: identical 3.84% golden mismatch on Windows.
   - `direct SharedPreferences opens stay inside reviewed adapters/stores`:
     baseline reviewed-call-count mismatch.
   - `device reset stops and deletes Dart and native diagnostics`: baseline
     source-marker `RangeError` in the Kotlin scanner.
5. Scoped analysis: no errors or warnings; 16 informational diagnostics, matching
   original upstream exactly after ignoring shifted line numbers. These concern
   existing main/Settings async-context/deprecation sites and Spotlight's
   existing parameter name/cacheExtent, not the port's added code.

The regression command used `flutter test --no-pub --reporter expanded` with:

```text
test/spotlight_board_scroll_motion_test.dart
test/tv_motion_profile_test.dart
test/settings_tv_motion_page_test.dart
test/spotlight_board_test.dart
test/spotlight_board_compact_test.dart
test/settings_appearance_groups_test.dart
test/settings_tv_spotlight_layout_test.dart
test/profiles/isolation_suite/stale_runtime_guard_test.dart
test/services/webdav_sync/webdav_sync_hot_merge_test.dart
test/profiles/profile_source_guard_test.dart
test/theme/shape_type_motion_test.dart
```

Exclusion expression supplied with `--name`:

```text
^(?!TV Spotlight settings visual|direct SharedPreferences opens stay inside reviewed adapters/stores|device reset stops and deletes Dart and native diagnostics)
```

Local raw evidence (ignored logs, not committed build artifacts), relative to
this note's directory:

- `upstream-tv-motion/red-spotlight.log`
- `upstream-tv-motion/red-root-subscription.log`
- `upstream-tv-motion/final-regressions.log`
- `upstream-tv-motion/upstream-baseline-tests.log`
- `upstream-tv-motion/analyze.log`
- `upstream-tv-motion/upstream-baseline-analyze.log`
