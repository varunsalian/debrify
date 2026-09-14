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

## Follow-up: mixed-direction browsing, September 9

The vertical-only result above was not sufficient. A new cold-cache run mixed
horizontal and vertical Home navigation with collection galleries and details.
It reproduced intermittent stalls and TMDB lists requiring Retry.

### Confirmed causes and changes

- VM CPU samples exposed additional synchronous sync work outside Flutter's
  frame-build measurements: publication change-detection hashes, incoming hot
  document parsing/authentication, and decoded section-cache size accounting.
  These now run in the bounded large-I/O worker, including unchanged sync
  cycles. Digest, schema, timestamp, content-hash and read-back validation are
  retained. Session validation follows publication preparation. Pending cache
  sizing cannot repopulate a cache cleared by a profile/session change.
- Android TV collection halos now cache the static blur independently and
  animate opacity. A rendered pixel comparison matches the original fully
  focused appearance exactly. Disabled halos skip the decoration entirely;
  reduced motion is respected. The non-Android path, including tvOS, is unchanged.
- Background IMDb identity enrichment yields to active catalog requests.
  Catalog retries use fresh transports, bounded backoff and the existing total
  deadline; identity requests retain their full three-second completion budget.
  Authentication errors and rate limits are not blindly retried.
- The Mi Box resolved the main TMDB hostname to `49.44.79.236`. A credential-free
  Android Java HTTPS probe timed out three times, while `api.tmdb.org` returned
  the expected unauthenticated 401 three times (753–1180 ms). Public-DNS routes
  to the original hostname also suffered HTTP connection resets in Debrify;
  rotating IPs alone did not fix this. This establishes a route/hostname-specific
  problem on this network, not the precise upstream cause or owner of the reset.
- Idempotent TMDB v3 reads now opt into a short-lived alternate-host fallback
  after transport failure. Both hosts use their own normal TLS hostname and
  certificate verification. No third-party API proxy is used. The alternate
  hostname is under TMDB's `tmdb.org` domain (also used by its documented
  [image service](https://developer.themoviedb.org/docs/image-basics)); its root
  redirects to TMDB's API documentation. Other providers, image requests,
  HTTP URLs, nonstandard ports and credential-bearing authority URLs are not
  rewritten. Failure of the alternate permits return to the primary route,
  with a cooldown; healthy normal routes need no failover.

### Measured and tested

- Matched 14-key mixed-navigation profile traces: UI-frame p95 6.46 → 6.19 ms;
  raster p95 17.38 → 16.36 ms, maximum 52.68 → 35.66 ms. The final 366-frame
  trace had no UI frames over 16.67 ms or raster frames over 50 ms. The expensive
  sync hash/parse stacks no longer dominated main-isolate CPU samples.
  This is profile-mode evidence, not a guarantee of 60 FPS; CPU work outside
  frames, GC, input cadence and OS scheduling require separate interpretation.
- A&E's three-list gallery and Action's eight-list gallery loaded on the Mi Box
  without Retry after failover, including the lower rows. Previously A&E failed
  repeatedly. The Mac's 48-source Kaptain cold/warm integration check also passed;
  Mac success alone was not accepted as evidence of TV network reliability.
- Final focused gate: 239 tests passed across collection reliability, native
  sources, TLS/routing, metadata, glow pixels and sync engine/worker/shard tests.
  The broad suite reported 5,812 passes, 10 skips and 18 failures: the 17 known
  baseline failures plus an unrelated UDP-transfer temporary-file cleanup race.
  All 17 transfer tests passed on isolated rerun. Analysis of changed production
  modules found no errors/warnings and three brace-style informational notices.
- Cache-only clearing was verified again: 107 MB → 36.86 kB. Profiles/settings
  and the original 38,798,238-byte backup archive remain. Release APK installed
  in place at 16:35:27; Android flags confirm it is not debuggable. TMDB build
  configuration was checked in its ARM binary without printing credentials.
  APK SHA-256: `ee12b5cf4579956bef327a4a318626b3a6fa5ee6faa52bedde3ceefed48bc664`.

Follow-up changes are not yet committed or pushed. The earlier release hashes
and review rounds above describe earlier work, not this follow-up patch.

### Follow-up release browsing gate

- After the second cache clear, the release retained PID 8948 through more
  than six minutes of mixed-direction Home browsing, Hulu gallery, its New
  Series grid, Soy Luna details, horizontal episode/cast navigation, return to
  Home, A&E and Adventure galleries. No Debrify crash, ANR or process-death event
  appeared in the captured event log. No playback or setting changes were made.
- Hulu's visible TMDB/Trakt cards, all three A&E lists, and Adventure's visible
  TMDB lists (including all eight after scrolling) loaded without manual Retry.
  Series artwork, episode descriptions
  and cast loaded. Returning to Home and pressing OK reopened Hulu, confirming
  the originating collection focus was retained. One transient UI-dump failure
  was retried and verified rather than treating stale labels as evidence.
- Sampled release PSS was approximately 229–282 MB across those destinations;
  returning to Home measured 255 MB and reopening Hulu 235 MB. This is a short
  navigation soak, not a long-session leak guarantee.
- A first episode-navigation pass still had a SurfaceFlinger desired-to-present
  maximum of 140 ms (p95 81 ms); the subsequent warm pass measured maximum
  58 ms (p95 42 ms). These include compositor queuing and are not Flutter
  build/raster times or direct input-latency measurements. A remaining cold-load
  hitch is therefore explicitly not claimed fixed or proven to have a single
  cause. The device is improved, not universally lag-free.
- An additional 21 transition, image recovery and Spotlight policy tests passed.
  Combined with the main focused gate, 260 focused tests passed.
