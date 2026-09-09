# Android TV progressive loading

Implementation follow-up to [the performance assessment](tv-performance-research.md), September 9, 2026. Base commit: `53a6a1e386d2ff73ce61d0a6a53be6b0f69d62e9`.

## Changes

- Android TV Showcase no longer waits behind the opening cover for optional metadata and offscreen artwork. Valid actions are available immediately; their own prerequisite checks remain in place.
- Lower Showcase bands retain their layout and DPAD targets, but image widgets start loading only near the viewport or when their band receives focus. Admission is retained for the mounted band's lifetime. The existing placeholders and image dimensions are unchanged.
- Initial Android TV Home publishes saved collection folders first, then completed catalogs and tracker rows independently. Subsequent arrivals are coalesced over 32 ms rather than awaiting the slowest catalog in the batch.
- Canonical row ordering, existing row objects, horizontal paging state and focus nodes are preserved. Classic and Spotlight adjust the scroll offset before layout when rows arrive above the active card. Stage layouts retain their active rail identity.
- Classic retains a short batch's unused bottom space when necessary to prevent scroll clamping from moving its active card after insertion. Android TV Atrium's label line height now matches its existing reserved height, avoiding a small overflow when a partial row appears.
- Partial loads preserve safe pagination cursors. Recovery fills the original catalog slots without replacing already-paged rows or appending duplicates. Pagination requested during initial loading resumes when the loader releases its cursor.
- New Home rows are retained as data while another route covers Home and applied on return. New work remains generation- and profile-session-guarded.

This does not cancel all existing background requests. Independently selected hero metadata can still resolve while Home is covered, and already-admitted image requests are not cancelled. App-wide concurrency tuning and a native Android rewrite are not part of this patch.

## Platform boundaries

The new loading policy is Android TV-specific. tvOS retains the composed opening gate and its animation. Phone/Mac, Search, Discover and existing preserve-visible-rows Home refreshes retain their prior publication behavior. No player, sync, account credential, storage-format or remote-control changes are included.

## Verification

Initial implementation run: **273 tests passed across 20 focused suites**. Targeted analysis reported no errors; the existing unused `_plateFill` warning and 19 informational diagnostics remained. `git diff --check` passed.

Local regression coverage includes production Home screens with one fast and seven deliberately delayed catalogs, mixed arrival order, focus and scroll anchoring, route cover/return, and Down pressed before the next batch can start. Fixtures use synthetic catalogs and mocked HTTP, not account credentials or the user's servers.

The production-screen matrix covers Classic, Canvas, Spotlight, Promenade, Deck, Atrium, Tonight and Mosaic on a 1280×720 test surface. Its independently selected hero is pinned to a fixture catalog so random hero prefetch cannot masquerade as board pagination.

Other focused checks cover early saved collections, tvOS's original waiting behavior, profile-session invalidation, timeout retirement and cursor recovery, retained horizontal pages, optional-metadata opening, offscreen artwork admission, disposal, idle frame scheduling, collection reliability, image sizing and existing page transitions.

Timeline markers `Home.loadStarted`, `Home.contentPublished`, `Showcase.mounted` and `Showcase.firstContentFrame` support a later profile capture. They are application/frame-boundary events, not measurements of GPU presentation or input-to-visible latency.

### Review follow-up

All three progressive-pagination review findings were valid and fixed:

- Automatic vertical paging stops while Android TV Home is covered. The remaining rows of an already-started batch may finish, but empty batches cannot keep scanning subsequent catalogs in the background. Returning applies deferred rows before measuring the viewport and resuming paging, including returns with no new rows.
- Horizontal page completion finds the same section at its current index before updating items, cursor and focus nodes. Removed/replaced sections and changed profile sessions still reject late results.
- Deferred Down distinguishes reserved, in-flight rows from catalog exhaustion. All eight Home layouts are covered, including Spotlight's independent navigation implementation. Intentional rail replacement can restore detached focus, while sideways movement and covering routes cancel pending navigation.

The follow-up added 16 production-screen regression tests. A negative-control run temporarily disabled the three fixes and reproduced background catalog requests, a discarded 100-item horizontal page, and ignored Down navigation; the fixes were restored immediately afterward. That run passed **289 tests across 21 focused suites**. Analysis of the changed Home code and tests reported no errors or warnings, with 19 pre-existing informational diagnostics. No device interaction or deployment was performed during that review-fix pass.

### Sidebar backdrop follow-up

- Android TV removes Home's shared backdrop immediately when another sidebar tab is selected, including any artwork retained by an in-progress crossfade.
- Tab changes use one 150 ms incoming fade, without the additional whole-content fade. Outgoing pages are unmounted in the same frame, preventing an old Home's delayed cleanup from clearing a rapidly reopened Home's artwork.
- Home's own artwork crossfades, same-tab state and focus, and the existing tvOS and non-TV transition behavior remain intact.

Ten additional regression tests cover backdrop isolation, rapid switches, unchanged platform behavior, and leaving/reopening the production Classic and Spotlight Home screens during pending catalog loads. Disabling the backdrop fixes reproduced four failures; the fixes were restored before the passing run. **329 tests passed across 25 focused suites**. Targeted analysis found no errors or warnings; ten existing informational diagnostics remain in `main.dart`.

The Android ARM release was rebuilt with the local TMDB configuration verified in its compiled binary, signature-verified, installed over the existing Mi Box app, and launched on September 9, 2026. App data and settings were preserved. No secrets are included in the source changes or fixtures.

## Remaining device validation

The user is testing the installed build; no new on-device performance benchmark was collected for these changes. Actual Mi Box responsiveness and memory improvements remain unmeasured. When authorized, compare cold/warm Home and detail entry, repeated horizontal/vertical navigation, return focus, frame timings and memory over a longer session. Tests do not establish that all lag or crashes are eliminated.
