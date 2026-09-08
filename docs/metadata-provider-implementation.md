# Selectable metadata providers

Implementation scope: phases 1–5 requested on 2026-09-07. Leave all changes
uncommitted. Existing behaviour is the default; optional new sections default off.

## Acceptance checklist

- [x] Phase 1: profile-scoped category selectors, provider capabilities, explicit
  fallback, language/region preferences, shared cache and bounded networking.
- [x] Phase 2: titles/descriptions, posters, backdrops/logos on Home, search,
  collections, Continue Watching and details. Preserve content/source identity.
- [x] Phase 3: selectable cast/crew and episode description/artwork. Never change
  stream IDs, episode numbering, watched state or resume progress.
- [x] Phase 4: selectable trailers/recommendations, trailer language/candidates,
  optional franchise rail; preserve existing autoplay and platform lifecycle.
- [x] Phase 5: optional person pages, linked company/network browsing, regional
  availability and expanded discovery filters.
- [x] Review 1: default behaviour and integration coverage.
- [x] Review 2: malformed data, unavailable providers, timeouts, profile changes.
- [x] Review 3: touch/remote navigation, video lifecycle and performance.
- [x] Review 4: regression tests, targeted analysis and final scope audit.

## Invariants

Provider choice is per category, not a global TMDB replacement. Installed addons
are listed by name only for supported capabilities. Current behaviour means the
original code path, including its existing fallback policy. Explicit choices do
not implicitly permit another provider; fallback is a separate setting. Source
identity, tracker state, episode numbering and playback selection are never
metadata-enrichment outputs. TMDB ratings must never be labelled IMDb ratings.

Language settings affect TMDB requests only. Cache identities include language,
region and provider configuration. Profile changes must not apply stale results.
Discovery and auxiliary sections are opt-in. No credentials enter settings,
diagnostic logs or source control.

## Implementation map

| Phase | Main implementation | Verification |
| --- | --- | --- |
| 1 | Metadata preferences model/service, Metadata settings page, TMDB repository | Defaults, independent selections, capabilities, profile isolation, portability, cache and transport tests |
| 2 | Presentation service/mixin, catalog tiles, Home/Spotlight, Discover and detail hosts | Identity preservation, language/fallback, batching and existing layout regressions |
| 3 | Details/episode services, EpisodesPanel, EpisodeArtworkService | Credits, stable episode coordinates, provider failure/retry and Continue Watching regressions |
| 4 | Selected trailers/recommendations and MetadataFranchiseRail | Trailer lifecycle, navigation, default-off and late-load invalidation tests |
| 5 | MetadataExploreService/Page, Discover source action, collection filters | Entity browsing, regional availability, malformed responses, filtering and remote action tests |

Classic detail pages display the optional franchise rail inline. Alternate
layouts expose it and other optional sections through their registered Explore
action. TV Discover uses the existing Source selector; touch also has a shortcut.

Preference changes refresh mounted content and reject stale profile results.
Addon caches distinguish configurations. Sanitized exports accept only canonical,
credential-free metadata preferences. Sync refreshes use the local revision path.
Metadata never changes tracking, stream bindings or episode identity.

## Review evidence

### Review 1 — default behaviour and integration coverage

Reviewed the default provider paths, identity preservation and detail layout
integration after the initial implementation. All 1,198 tests in the combined
metadata, detail-layout/theme, DPAD, Showcase, Spotlight and settings run passed
(`/tmp/debrify-metadata-review1-tests.log`). The tests exercise existing defaults
and layouts; they do not establish every optional live-provider response.

### Review 2 — failure handling and profile changes

Found and fixed two CW artwork failures: a profile preference read could escape
as an error, and null results from an unavailable explicit provider remained
cached. Explicit artwork now retries failed lookups and retains successful
results. Secondary language/image reads now retain the tile's relevance guard.
The failure/transport suite passed 27 tests
(`/tmp/debrify-metadata-review2-tests.log`). Earlier portability, sync refresh,
Discover-query and profile tests passed 98 tests. Synced metadata policy now
bumps the same revision as local edits, behind the authorization barrier.

### Review 3 — navigation, lifecycle and bounded work

Verified narrow 320px screens with enlarged text, remote provider selection,
franchise activation and late-load invalidation. Found that independent floating
controls are a poor TV entry point for layouts with explicit focus graphs.
Explore is now a registered detail action in all alternate layouts, including
Showcase; its franchise rail remains in the Explore page rather than inserting
an unregistered band into Showcase. Classic details also show an inline franchise
rail. TV Discover exposes TMDB through its Source selector; touch also has a
shortcut. The 118-test DPAD/Showcase/settings/franchise run passed
(`/tmp/debrify-metadata-review3-layout-tests.log`).

Custom recommendation renderers now receive ordered presentation batches of four;
they keep their initial rail and stop requesting new batches after invalidation.
The related 18 tests passed. The final macOS release build subsequently passed in review 4.

### Review 4 — final regression and scope audit

The combined final run passed **1,386 tests** across metadata, transport,
collections, profile portability/sync refresh, episode progress, Continue Watching,
detail layouts, remote navigation, Spotlight and trailer lifecycle
(`/tmp/debrify-metadata-final-tests.log`). These are overlapping regression suites,
not a count to add to earlier review runs.

Targeted analysis of 36 implementation files reported no errors; the 25 existing
diagnostics were checked against HEAD. Subsequent analysis of the repository and
its retry tests reported no issues. The macOS release build succeeded
(`/tmp/debrify-metadata-final-macos-build.log`).

A live repository smoke test passed for localized movie details, images, trailers,
TV seasons, aggregate credits, people, franchises, discovery and language
configuration. Probes encountered occasional connection resets with both standard
and custom clients; no specific transport root cause was established. Public GET
reads now retry a transport exception once within the original timeout budget,
closing the failed client first. Tests cover cancellation and the two-attempt cap.
Network/provider failures remain possible and are handled as unavailable data.

The final auxiliary-action audit also catches browser-launch failures and displays
an error. Source-control checks found no credentials in the task files and no
whitespace errors. All implementation changes remain uncommitted.

## Validation limits

The release build was verified on macOS. Touch and remote navigation were covered
by widget tests, including narrow screens and enlarged text; this pass did not
install or manually exercise every physical target platform. Live API coverage is
a smoke test, not an assertion that all provider accounts or regional networks
will succeed. Existing provider behaviour remains the default and optional
features remain off until enabled.

## Follow-up review — detail information policy

Fixed runtime and genre consumers in both classic detail hosts and the shared
alternate-layout model. Explicit information choices use presented fields; absent
fields may use IMDb only with fallback enabled. Current behaviour retains the
existing precedence. Suppressed IMDb enrichment also clears runtime minutes and
genres while preserving ratings and independently selected credits.

The follow-up run passed 1,055 tests, including a provider-to-detail-model matrix
for populated/missing fields and fallback on/off. Targeted analysis reported only
the existing onPopInvoked deprecation. Changes remain uncommitted.

## Follow-up review — native Explore and monetization regions

Both Search detail routes now supply title navigation independently of the IMDb
recommendation loader, allowing unmapped TMDB titles to open Explore. A widget
test opens Explore from a native title without that loader and checks onward
navigation. Monetization-only Discover filters now supply the existing US region
default while retaining explicit regions; tests cover movies, TV and empty filters.

All 63 targeted navigation, Explore, native-source and detail playback tests passed.
Targeted analysis reported existing informational diagnostics only. Changes remain
uncommitted.

## Follow-up review — interrupted background preference reads

Hero enrichment, the hero trailer timer and detail trailer loading now use a
failure-aware background preference read. Invalidated or failed reads discard
the attempt rather than assuming defaults or escaping as asynchronous errors.
The hero trailer clears its loading indicator, and successful late reads are
checked against caller ownership before starting provider work.

All 31 targeted preference, navigation, detail playback and trailer tests passed.
The new tests cover asynchronous invalidation errors, stale successful results,
skipping departed callers and recovery on a later attempt. Analysis reported
existing informational diagnostics only. Changes remain uncommitted.

## Follow-up review — stage Home metadata policy

Hero provider results now carry their policy in an authoritative snapshot, distinct
from sparse legacy enrichment. Stage identity and compact identity consumers use
selected titles and preserve absent information fields. Stage art and shell art
respect selected backgrounds and disable original, derived Metahub and poster
fallbacks when cross-provider fallback is off. Legacy sparse enrichment retains
its existing behaviour.

All 77 targeted policy, stage collection, provider, Spotlight and trailer tests
passed. Analysis reported no errors or warnings. Changes remain uncommitted.

## Follow-up review — trailer handoff and image errors

Discover publishes presented metadata when streams start, preserving enrichment
that arrived before trailer resolution. Spotlight card image-error fallback now
respects the applicable artwork selector and fallback policy, uses the presented
poster when allowed, and preserves independent episode artwork handling.

All 83 targeted Spotlight, Discover, provider and image-fallback tests passed.
The six new policy tests cover fallback off/on, absent selected posters, independent
poster selection, defaults and episode art. Existing Discover tests cover layout
and trailer-stage behaviour; this run did not exercise live YouTube resolution.
Analysis reported two existing informational diagnostics. Changes remain uncommitted.

## Follow-up review — hero fallbacks and ambient refresh

Compact and wide Spotlight heroes now gate missing-backdrop and image-error poster
fallback on the background policy. Classic Home hero applies the same guard.
Spotlight republishes after presentation resolves, invalidates old tint probes,
clears ambient artwork for empty results and publishes the chosen URL immediately
while tint extraction runs. Resetting to current behaviour also notifies consumers.

All 83 targeted hero, Spotlight, metadata and Discover tests passed, including
compact/wide widget tests for clearing disallowed artwork and restoring ambient
artwork after reset. Targeted analysis reported existing informational diagnostics
only. Changes remain uncommitted.

## Follow-up review — detail backdrop fallback

Both detail hosts and DetailModel now share the backdrop policy resolver. An
explicit backdrop selection with fallback disabled leaves missing backdrops empty;
poster presentation remains independent. Current behaviour retains its original
poster fallback. Eight new cases cover current/explicit selection, fallback on/off
and populated/missing backdrops in both the shared resolver and layout model.

All 1,069 targeted detail, metadata, layout, navigation and playback tests passed.
Analysis reported only the existing onPopInvoked deprecation. Changes remain
uncommitted.
