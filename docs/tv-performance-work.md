# TV responsiveness work — September 2026

## Scope and safety

Investigate Home/navigation stalls and crashes on the user's Mi Box, retain
visual quality and durable profile data, implement lightweight page/image
transitions, and perform multiple review/test iterations. Completion requires
on-device verification, not only local benchmarks.

- Baseline: `3f8a5026`, which already moves sync merge/publication hashing and
  Home collection signatures off the UI isolate.
- Device: MIBOX4, Android 9, 32-bit ARM app, approximately 2 GB RAM, 1080p60
  display. Profile APKs are release-signed updates; no uninstall or data reset.
- Today's manually created `.debrify` archive remains on-device; an additional
  copy is in a private temporary directory on the development Mac.
- TMDB configuration is supplied privately at build time. No keys or user
  preference payloads are checked in.

## Implemented in the working tree

1. TV routes use 180 ms forward / 140 ms reverse fades. The previous fade only
   occupied the first portion of a 300 ms route animation. Phone transition
   defaults are preserved. Reduced motion skips the fade. Curve animation
   adapters do not accumulate undisposed status listeners.
2. Ready TV artwork uses a single short reveal, without an additional fading
   placeholder. Spotlight previously inherited a 1,000 ms placeholder fade.
   Decode resolution, image cache limits and artwork sources are unchanged.
3. Owned Home collection tiles reuse their attached folder presentation data.
   Index/identity checks retain ID-lookup fallback for replaced, copied and
   foreign definitions; duplicate IDs retain first-match fallback. This avoids
   repeated linear scans and encoded-ID allocations during ordinary row builds.
4. Android TV rich focus uses the lightweight moving state for deliberate as
   well as rapid movement, then restores its rich stationary highlight. Final
   scale and appearance are retained. Non-Android-TV spring behavior remains.
   Generation guards reject stale animation completions after interruption or
   disposal.
5. Normal catalog cards reuse immutable presentation descriptors through a
   weak-key cache. Metadata identity, effective IMDb identity, source addon and
   orientation invalidate the descriptor. Navigation callbacks capture their
   source rather than a mutable row index. Dynamic collection/continue-watching
   branches remain uncached; no additional decoded-image cache is introduced.

## Evidence collected so far

- Actual Mac inventory: 18 collections, 756 folders, 3,545 sources. Ten row
  presentation passes initially took approximately 81 ms; the final guarded
  fast-path diagnostic took 1.11 ms. This is a component benchmark, not a TV FPS claim.
- A verified Home vertical traversal before the new motion changes recorded
  314 Flutter frame spans: UI p95 17.389 ms; raster-stage p95 47.587 ms.
  Swap/presentation waits are reported separately: `GPURasterizer::Draw` alone
  must not be interpreted as pure rendering cost.
- Initial page/image/lookup improvements did not eliminate the high raster
  tail. With the lightweight moving focus state, a matching traversal recorded
  UI p95 9.291 ms and raster-stage p95 8.353 ms (maximum 13.457 ms for that
  raster stage). UI outliers still occurred; this is not a perfect-FPS claim.
  These profile-mode captures precede the final descriptor cache and lifecycle
  guards, and must not be presented as exact final-release FPS measurements.
- Final broad working-tree suite: 5,797 passed, 10 skipped,
  17 failed. Clean baseline suite: 5,788 passed, 10 skipped, 19 failed.
  Failure-name comparison found no new failures; the two corrected compact
  Home tests lacked mocked preferences. Other baseline failures remain and
  must not be described as a green full suite.

## Review iterations

- Round 1: checked folder fast-path ownership, foreign metadata, replacement
  behavior, duplicate-ID fallback and unchanged folder navigation. Added tests
  for arbitrary foreign tiles and in-place definition replacement.
- Round 2: checked route durations, reduced motion, cancellation, animation
  listener lifetime and non-TV behavior. Added focus interruption coverage and
  stale-completion guards. Focus/page lifecycle suite: 25 passing tests.
- Round 3: checked weak-cache retention, source provenance after row changes,
  orientation/metadata invalidation, and late resolved identities. Added
  duplicate-folder-ID and late-identity regression coverage. The final focused
  gate passed 49 tests; the 3,000-card/ten-rebuild test avoids repeated artwork
  derivation. Broad-suite failure-name comparison found no new failures.
- Final release/device gate: completed. Signed release installed in place
  with the TMDB configuration verified in its ARM binary, no debug flag, and
  profile data preserved.

## Final device and regression gate

- Final APK SHA-256:
  `171c872c77cbfa9a629d16c9a45a4a9fde4b2b334488d6faca4c576fb4ccc55d`.
  Version code 44, installed September 9 at 15:05:34. The TV remains on this
  release, with the original 38,798,238-byte backup archive intact.
- Six release-mode navigation cycles (353 seconds total), each traversing ten
  rows down/up and opening/returning from details, retained PID 25795. No new
  Debrify ANR, crash, or process-death events appeared in the event capture.
  Cycle-end PSS in KiB: 224661, 238983, 233002, 234842, 231284, 232262.
  Warmed-up readings did not show sustained growth. This short soak is not
  proof against every long-session leak or crash.
- Separately verified details opening, Spotlight collection gallery, its
  Pedro Pascal TMDB list, vertical/horizontal grid navigation, and loaded
  artwork. Returning twice restored the Home collection position; pressing OK
  reopened that same collection without additional navigation or Retry.
- Image failure/retry and reduced-motion paths are covered by widget tests.
  The additional sync/collection gate passed 189 tests, including engine,
  merge/publication and collection-section tests. Final release logs did not
  expose sync activity, so this is not a claim that a live WebDAV cycle was
  observed during the soak. The original diagnosed publication/hash ANR path
  is off the UI isolate in both normal and recovery engine paths.
- All three review iterations are complete; no new broad-suite failure names
  relative to clean HEAD. Existing unrelated test failures remain documented
  above. New work is uncommitted and has not been pushed.

## Limits

The measured Home render improvement is substantial, but slow remote artwork,
provider responses, video playback and OS scheduling can still affect perceived
responsiveness. Neither this test run nor the changes establish universal
60 FPS or a guarantee of no future crashes. Artwork resolution and the final
stationary focus appearance were preserved.
