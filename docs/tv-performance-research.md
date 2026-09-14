# Android TV responsiveness and native UI assessment

## Recommendation

Keep the current Flutter application for the next performance iteration. First remove unnecessary waits before usable content appears, then control the amount of artwork and background work competing with navigation. Evaluate a Kotlin/Compose TV prototype only if those changes leave unacceptable rendering or input latency on the target hardware.

Two concrete loading decisions deserve priority over another graphics toggle. Showcase details deliberately hide the page and exclude its controls from focus during a TV-only opening gate. Home also withholds its board until a catalog batch and optional tracker rows finish, even when collection-folder tiles are already available locally. These are source-confirmed explanations for perceived slowness; their contribution to the remaining on-device lag still needs an isolated comparison.

A native Android UI is a viable architectural option, not a guaranteed cure. It would still need progressive loading, correctly sized images, bounded work, and stable focus. The immediate objective should be a responsive first screen with the existing appearance—not waiting for every secondary section to finish before showing anything useful.

## Scope and evidence

This assessment covers Android TV, especially the previously tested MIBOX4: Android 9, approximately 2 GB RAM, a 32-bit ARM build, and an older GLES 2-class GPU. It does not recommend changing Apple TV behavior. Repository findings refer to Debrify commit `53a6a1e386d2ff73ce61d0a6a53be6b0f69d62e9`, inspected on September 9, 2026.

No new TV interaction or device benchmark was performed for this assessment. Existing device captures, current source, three local Showcase regression tests, official platform guidance, and the public Nuvio TV implementation provide the evidence. Local tests establish behavior, not Mi Box frame rates.

| Evidence | Finding | Interpretation |
| --- | --- | --- |
| Current code and three passing widget tests | Showcase's TV opening gate hides content, delays entry focus, and respects deliberate focus movement | A real presentation delay; not proof of the entire app's remaining lag |
| Current Home loader | Initial catalog results are batched behind `Future.wait`; tracker rows share the final publication point | A slow request can hold back already available board content |
| Previous mixed-navigation profile capture | Final UI p95 approximately 6.19 ms; raster p95 16.36 ms and maximum 35.66 ms | Rendering still has little headroom at 60 Hz, despite earlier improvements |
| Previous release episode-navigation capture | Cold desired-to-present p95 81 ms; warm p95 42 ms | Cold/warm presentation differs; this is not direct input latency or Flutter raster time |
| Previous short release soak | PSS approximately 229–282 MB; no captured crash/ANR | Useful stability evidence, not complete graphics accounting or a long-session guarantee |
| Reported trailer-setting experiment after restart | Little noticeable improvement | Downgrade this as the leading explanation; there is no measured A/B benefit here |

Historical measurements and their qualifications are recorded in [TV responsiveness work](tv-performance-work.md). Its earlier installation and working-tree status notes describe successive snapshots, not the present branch state.[^1]

## 1. Detail-page opening

### Current behavior

In [`detail_layout_showcase.dart`](../lib/widgets/detail/detail_layout_showcase.dart), `_usesTvOpeningGate` applies when DPAD is enabled and `PlatformUtil.isTelevision` is true. Consequently, Android TV and tvOS take this path; ordinary phone and Mac navigation do not. `_openingMinimum` is 180 ms and `_openingTimeout` is 1,200 ms.

The gate first waits for opening metadata and the hosted episode view. It then uses the remaining deadline to precache a snapshot of image providers. The provider list can contain up to 27 distinct images: one backdrop, one logo, six episode stills, seven cast portraits, six recommendations, and six universe posters. Actual counts depend on available data and duplicate URLs.

While this happens, the real page is mounted at near-zero opacity beneath a static cover. `ExcludeFocus` and `IgnorePointer` keep its controls unavailable. The near-zero opacity intentionally permits painting and texture uploads before reveal. Additional frame boundaries and a 180 ms reveal mean the 1,200 ms readiness deadline is not a strict upper bound on total perceived opening time.

For merged series, [`_loadShowcaseOpeningData`](../lib/screens/merged_series_detail_screen.dart) waits for bound sources, enriched metadata, IMDb enrichment, parental guidance, and recommendations before marking opening data ready. Several are useful enhancements but need not prevent the title header or already valid actions from appearing.

This design has a legitimate purpose: hiding partial assembly and spreading cold texture uploads. It also trades away responsiveness. Simply deleting the gate without controlling the underlying work could restore the earlier reveal hitch.

### Recommended change

For Android TV, split the page into immediately usable content and independently loading sections. Show the selected title's existing name, artwork or stable placeholder, and valid actions immediately. Do not enable an action before its actual prerequisites are satisfied, but do not block unrelated controls on recommendations or parental guidance.

Prioritize the visible hero and first relevant row. Defer lower cast, recommendation, and universe artwork until it approaches the viewport. Retain a short, measured transition and stable dimensions rather than a full-page wait for secondary data.

Focus behavior must remain explicit. Keep a predictable entry target, preserve navigation to Back or other shell controls, and never steal focus when an asynchronous section completes. The existing 1,200-logical-pixel scroll cache also keeps upcoming DPAD targets mounted; reducing it requires a mount-and-focus strategy, not just a smaller number.

The three existing tests for the opening cover, pending metadata, and preservation of deliberately moved focus pass locally. A redesigned Android TV path needs new first-interaction tests while retaining the tvOS expectations. Source locations: Showcase lines 298, 438, 513, and 1192; merged series line 658.[^2]

## 2. Home's first useful content

### Current behavior

[`SearchScreen._load`](../lib/screens/search_screen.dart), which also loads Home, reads profile preferences and collection definitions before fetching the initial board. Optional tracker rows begin in parallel with a five-second completion deadline. Hide watched can additionally wait up to 1.5 seconds for its first local snapshot.

The initial catalog loader runs up to eight catalog requests together and awaits their combined result. It may advance through further batches if earlier catalogs are empty. Only after this and the tracker future complete does `_load` assemble the collection sections, assign `_homeSections`, and clear `_loading`. Until then, `_buildBoardContent` returns the branded loading stage.

The tracker deadline is not an extra five seconds added after every catalog batch: those tasks overlap. Nor is every Home visit necessarily a cold reload; an existing `preserveVisibleRows` path retains eligible rows. The issue is the first-load publication dependency, not the mere use of parallel requests.

### Recommended change

Publish eligible local collection tiles and valid profile-scoped cached rows first. Let catalog and tracker rows update independently, with a stable planned order and restrained update frequency. Use localized placeholders or row-level retry for unavailable content instead of holding the whole board behind one provider.

Preserve row identity and the focused content ID as data arrives. Reserve row positions where appropriate, or postpone structural insertion above the active row until it will not move the viewer's position. Otherwise an apparent speed improvement can introduce the focus jumps previously reported.

This is a medium-sized loading-state change rather than a one-line timeout adjustment. It must preserve generation guards, stale-result rejection, pagination cursors, search/Home separation, hidden rows, watched filtering, and profile isolation. A slow or failed provider should not erase unrelated successful rows. Source locations: `search_screen.dart` lines 2643, 2715, 2775, 2872, and 17938.[^3]

## 3. A useful app-wide performance policy

The useful global lever is a coordinated work budget. It should govern when optional work starts, how much remains active, and what is retained—not merely switch off animations. Debrify already has local cache limits, background-worker improvements, and some request prioritization; the remaining recommendation is to coordinate competing work across screens.

Classify work by urgency: the selected title and visible content first; the next navigation neighborhood second; distant enrichment and refresh last. When a route is covered or disposed, stop scheduling its optional work, cancel owned operations where cancellation is supported, and reject late results otherwise. A timeout that stops awaiting a future does not itself cancel its underlying work.

Use separate accounting for network requests, metadata processing, image decoding, and first presentation. Capping HTTP concurrency alone does not prevent a group of cached images from becoming ready together and causing upload work. Concurrency values should be benchmark parameters, not invented universal constants.

Separate memory classification from GPU capability. Android's low-RAM device signal is relevant to memory policy; GLES level is a capability hint, not a complete performance score. A roughly 2 GB box can be GPU-limited without being classified as low-RAM. Google's [TV memory guidance](https://developer.android.com/training/tv/playback/memory) supports device-aware budgets and warns that older devices may omit graphics memory from reported totals.[^4]

### Cache and image sizing

Debrify already caps Flutter's TV image cache at 140 entries and 56 MiB, with a separate smaller tvOS low-memory setting. Its shared disk image cache is also already present. “Add caching” is therefore not a diagnosis.

The 56 MiB setting must not be treated as a ceiling on all image or graphics memory. Flutter separately tracks live and pending images; rendered textures, surfaces, player buffers, and other allocations require separate accounting. Flutter's [ImageCache API](https://api.flutter.dev/flutter/painting/ImageCache-class.html) exposes these distinctions.[^5]

Instrument cache bytes, live and pending counts, active image requests, decode dimensions, route retention, and process memory together. Avoid increasing cache size until eviction and re-decoding are shown to dominate. Avoid indiscriminate clearing too: it can make ordinary navigation repeatedly behave like a cold launch.

Match decoded image size to the actual rendered surface and slot. Existing detail artwork already uses size limits, so this calls for targeted validation of mismatches and first-visible bursts, not a blanket reduction in poster quality. Preserve recent metadata and navigation anchors in a bounded cache without retaining every detail subtree and its image listeners.

Google's 1 GB TV guidance gives a 280 MB total budget across specified categories and recommends keeping anonymous/swap plus graphics under 200 MB. Those figures are not directly comparable to the historical Mi Box PSS range, especially with incomplete graphics counters, and do not establish that this application passes a 1 GB-device memory target.[^4]

## 4. Existing switches and proposed alternatives

| Lever | Present evidence | Recommendation |
| --- | --- | --- |
| Lower-resolution Flutter surface | `computeRenderScale` already selects a 720-pixel-high buffer automatically for the weak-GPU branch, unless overridden | Verify effective runtime state during the next authorized test; do not claim this is a newly discovered optimization |
| Native Trailer Surface | Can change the Flutter surface's transparency at Activity creation; requires restart | Keep as a controlled experiment, not the leading fix after the reported negligible benefit |
| Hero artwork quality | Changes image dimensions, not the whole loading dependency graph | Tune only if decode/upload evidence justifies it; retain appearance by matching the display need |
| Impeller | Explicitly disabled in the Android manifest, with driver-compatibility rationale | Do not globally enable it on the Android 9/GLES 2 target as a supposed universal fix |
| Shader warm-up | No app-specific warm-up was found | Add only for traced shader compilation; it moves work into startup |
| Android Baseline Profiles / forced package compilation | Optimize ART-managed code; Flutter release Dart is already machine code | Consider for demonstrated native startup/plugin costs, not as a cure for Dart loading gates or Flutter raster work |
| Bigger heap/cache or removal of all motion | Hardware acceleration, large heap, release shrinking, and TV cache limits already exist | No blanket change; memory pressure and cold reloads can worsen, while visual identity is lost |

The render-scaling implementation changes surface dimensions and device pixel ratio together, preserving logical layout. Moving from 1080p to 720p geometrically reduces pixel count by approximately 56%; that does not predict an equal speedup. The code also documents pointer/accessibility-coordinate limitations in this mode, so it is not a free universal default. Existing native implementation: [`MainActivity.kt`](../android/app/src/main/kotlin/com/debrify/app/MainActivity.kt), especially lines 670–798 and 1008–1042.

Flutter's current [Impeller documentation](https://docs.flutter.dev/perf/impeller) describes Android API 29+ availability and legacy fallback for older or unsupported devices. The local Flutter tool reports 3.44.8, whereas the current documentation is presented for a newer release; any engine experiment must be verified against the actual engine and GPU, not copied from newer-platform defaults.[^6]

For Skia, the official [ShaderWarmUp documentation](https://api.flutter.dev/flutter/painting/ShaderWarmUp-class.html) recommends identifying compilation in traces, including `GrGLProgramBuilder::finalize`. A cold/warm improvement alone is insufficient: image I/O, decoding, uploads, caches, and scheduling also differ.[^7]

Flutter release applications compile to machine code and use Flutter's own rendering engine. Android's Baseline Profiles target ART code paths and startup DEX layout. The inference is that those profiles can help relevant Java/Kotlin portions of Debrify but cannot optimize away its Dart-level readiness checks or C++ raster work. See [Flutter architecture](https://docs.flutter.dev/resources/architectural-overview) and [Baseline Profiles](https://developer.android.com/topic/performance/baselineprofiles/overview).[^8][^9]

## 5. Native Android TV and Nuvio

Nuvio TV's public repository identifies its stack as Kotlin, Jetpack Compose, TV Material 3, and Media3. At inspected commit `7f18cec84acbbb282b4e425362aae26a869f38d5`, its Home code has an eager/deferred catalog split, bounded catalog concurrency, preservation of existing content on reload, placeholder rows, early-result publication, and an 800 ms safety flush for available catalog content. The default eager count is four, but its Grid layout is an explicit exception that loads all catalogs eagerly. These are implementation observations, not a same-device performance comparison. See its [README](https://github.com/NuvioMedia/NuvioTV/blob/7f18cec84acbbb282b4e425362aae26a869f38d5/README.md) and [Home catalog pipeline](https://github.com/NuvioMedia/NuvioTV/blob/7f18cec84acbbb282b4e425362aae26a869f38d5/app/src/main/java/com/nuvio/tv/ui/screens/home/HomeViewModelCatalogPipeline.kt).[^10]

Nuvio also has a [Baseline Profile generator](https://github.com/NuvioMedia/NuvioTV/blob/7f18cec84acbbb282b4e425362aae26a869f38d5/baselineprofile/src/main/java/com/nuvio/tv/baselineprofile/BaselineProfileGenerator.kt) covering horizontal and vertical navigation, detail entry, and return. This demonstrates attention to representative journeys, not evidence that its frame times or memory are lower than Debrify's.[^10]

Google presents [Compose for TV](https://developer.android.com/training/tv/playback/compose) as its modern Android TV UI approach, with TV-specific components and remote-friendly focus behavior. It supports custom styling, so choosing it would not require discarding Debrify's visual design. Google also provides a [JetStream TV sample](https://github.com/android/tv-samples/tree/main/JetStreamCompose) as an architectural reference.[^11]

### A bounded native prototype

If the next Flutter iteration still misses the agreed targets, prototype one native Home screen, one collection grid, and one series detail route. Use the same sanitized catalog snapshot, artwork, dimensions, focus treatment, and navigation sequence as the Flutter benchmark. Keep network latency out of the initial renderer comparison, then repeat with identical delayed and failing provider fixtures.

A reasonable starting stack is Kotlin with Compose for TV, lazy vertical/horizontal layouts, stable item keys, screen state outside composables, and a shared image loader with bounded caching. Compose still needs disciplined state handling: Google's [performance guidance](https://developer.android.com/develop/ui/compose/performance/bestpractices) recommends moving repeated calculations outside composition, using lazy-layout keys, and avoiding unnecessarily broad recomposition.[^12]

Treat this as a separate benchmark implementation initially. Embedding a native view into the existing heavy Flutter page would not isolate the benefit, while running two complete UI/state stacks can add lifecycle and memory cost. Only a measured win should justify production integration.

A production native TV client is a large project: profiles, encrypted storage and sync, addon contracts, collections, watched state, search, playback handoff, settings, deep links, and remote configuration must retain their semantics. Reusing contracts and fixtures is easier than assuming Dart service code transfers directly into Kotlin. Apple TV, phone, and Mac should remain outside that migration unless separately justified.

## 6. Visual quality and regression safeguards

Keep the current layout, readable text, artwork framing, stationary focus appearance, and short page/image transitions. Prefer animating a small already-rendered region or revealing only newly ready content, and measure any full-screen opacity overlap. No animation is literally free of CPU, GPU, or memory cost.

Flutter recommends controlling expensive effects and localizing rebuilds; an extra compositing layer or repeated painting can outweigh the apparent simplicity of an effect. This supports targeted changes, not removal of all fades or indiscriminate addition of repaint boundaries. See [Flutter performance best practices](https://docs.flutter.dev/perf/best-practices).[^13]

The mandatory regression cases are mixed-direction rapid DPAD movement, repeated keys, navigation before artwork completes, Back during loading, late section arrivals, slow or unavailable providers, watched filtering with remaining pages, and return to the original row/card. Add profile switch and logout during every pending load: cached content and credentials must not cross sessions.

Android TV-specific policy must not accidentally alter tvOS because both satisfy `PlatformUtil.isTelevision`. Preserve reduced motion and keyboard behavior as well as normal remote navigation. Test focus restoration without allowing late autofocus to override deliberate user movement.

## 7. Measurement and delivery order

Measure perceived waiting separately from frame rendering. Record route request, first useful content, first valid focused action, image readiness, and actual presented focus feedback. A page can have excellent frame timings while deliberately showing a loader for a second.

For Flutter, collect UI/raster timing and CPU samples, including work outside frame spans; correlate these with supported system scheduling and compositor traces. [Flutter's Performance view](https://docs.flutter.dev/tools/devtools/performance) distinguishes UI and raster work. Android cautions that its [render-time statistics](https://developer.android.com/topic/performance/vitals/render) do not cover every non-View/OpenGL rendering path, so a quiet `gfxinfo` or Android vitals result is not proof that Flutter is smooth.[^14][^15]

Do not assume newer Android tracing features exist on Android 9. Use what the device supports, identify the exact surfaces, and keep compositor desired-to-present statistics distinct from input-to-visible latency. Record build mode, effective renderer/surface resolution, network conditions, cache state, and thermal state for each comparison.

Suggested acceptance targets below are engineering goals for this application, not measured results or vendor guarantees:

| Journey | Initial acceptance target |
| --- | --- |
| Open a cached title | Useful title content and a valid focus target within 200 ms, without waiting for secondary services |
| Ordinary DPAD navigation | Presented focus feedback p95 below 100 ms; no lost or replayed focus moves after background updates |
| Mixed 60 Hz scrolling | UI and raster p95 each below 16.7 ms, preferably with substantial headroom; investigate every repeatable >50 ms app-caused stall |
| One slow Home provider | Available local/cached content remains usable; unrelated successful rows appear independently |
| Detail → Back | Restore the same content anchor without a whole-board loading replacement |
| Longer session | No sustained post-warm-up memory growth, repeated enrichment loops, crash, or ANR in the exercised paths |

Use repeatable horizontal-plus-vertical sequences, collection entry, series details, episode navigation, Back, and resume. Run at least 20–30 route repetitions for initial latency distributions, with cold and warm results reported separately, followed by a longer mixed-use soak. This is enough to expose recurring issues, not to prove the absence of rare failures.

Local tests can model delayed metadata, out-of-order rows, failed images, oversized collections, cancellation, and profile changes. A Mac or emulator cannot faithfully reproduce the Mi Box GPU driver, memory bandwidth, compositor behavior, or thermals. Real-device validation remains necessary when the TV is available.

Delivery order should be:

1. Add first-useful-content and focus-ready measurements; redesign the Android TV Showcase gate with visible-first artwork preparation. Scope: small-to-medium, with meaningful focus and image-lifecycle risk.
2. Publish Home content progressively while preserving stable order, pagination, and session boundaries. Scope: medium.
3. Coordinate optional work and image preparation across active/covered routes; tune budgets from traces. Scope: medium and cross-cutting.
4. Test renderer or shader changes only when the remaining trace identifies that cause. Keep each experiment isolated and reversible.
5. Build the native prototype only if the optimized Flutter path still fails the targets. The prototype is bounded; a production migration is substantially larger.

The expected first improvement is less unnecessary waiting with the same visual design. The amount of remaining frame-time improvement cannot be promised until those changes are measured on the target TV.

## Sources

Public sources were accessed September 9, 2026. Mutable documentation describes its current version; repository observations are pinned where material. Local evidence contains no credentials or exported account settings.

[^1]: Debrify, [TV responsiveness work](tv-performance-work.md), September 2026, particularly “Follow-up: mixed-direction browsing” and “Follow-up release browsing gate.” Historical device measurements and limitations.
[^2]: Debrify commit `53a6a1e386d2ff73ce61d0a6a53be6b0f69d62e9`, [Showcase layout](../lib/widgets/detail/detail_layout_showcase.dart), [merged series details](../lib/screens/merged_series_detail_screen.dart), and [Showcase tests](../test/detail_showcase_test.dart). Local source and three matching tests verified September 9, 2026.
[^3]: Debrify, same commit, [Home/Search screen](../lib/screens/search_screen.dart), [Home list rows](../lib/services/home_list_rows.dart), [image-cache setup](../lib/main.dart), [disk image cache](../lib/services/debrify_image_cache.dart), [Android Activity](../android/app/src/main/kotlin/com/debrify/app/MainActivity.kt), and [Android manifest](../android/app/src/main/AndroidManifest.xml). Local source access.
[^4]: Google / Android Developers, [Optimize memory usage on Android TV](https://developer.android.com/training/tv/playback/memory). Device classification, memory categories, 1 GB guidance, and incomplete graphics reporting.
[^5]: Flutter, [ImageCache class](https://api.flutter.dev/flutter/painting/ImageCache-class.html). Cache entries, live references, and pending image counts.
[^6]: Flutter, [Impeller rendering engine](https://docs.flutter.dev/perf/impeller). Backend availability and platform/version qualifications.
[^7]: Flutter, [ShaderWarmUp class](https://api.flutter.dev/flutter/painting/ShaderWarmUp-class.html). Trace-based diagnosis and startup trade-off.
[^8]: Flutter, [Flutter architectural overview](https://docs.flutter.dev/resources/architectural-overview). Release compilation and rendering architecture.
[^9]: Google / Android Developers, [Baseline Profiles overview](https://developer.android.com/topic/performance/baselineprofiles/overview), updated September 1, 2026. ART and DEX optimization scope.
[^10]: NuvioMedia, NuvioTV commit `7f18cec84acbbb282b4e425362aae26a869f38d5` from `dev`: [README](https://github.com/NuvioMedia/NuvioTV/blob/7f18cec84acbbb282b4e425362aae26a869f38d5/README.md), [HomeViewModel](https://github.com/NuvioMedia/NuvioTV/blob/7f18cec84acbbb282b4e425362aae26a869f38d5/app/src/main/java/com/nuvio/tv/ui/screens/home/HomeViewModel.kt), [catalog pipeline](https://github.com/NuvioMedia/NuvioTV/blob/7f18cec84acbbb282b4e425362aae26a869f38d5/app/src/main/java/com/nuvio/tv/ui/screens/home/HomeViewModelCatalogPipeline.kt), and [Baseline Profile generator](https://github.com/NuvioMedia/NuvioTV/blob/7f18cec84acbbb282b4e425362aae26a869f38d5/baselineprofile/src/main/java/com/nuvio/tv/baselineprofile/BaselineProfileGenerator.kt). Architecture observations, not performance measurements.
[^11]: Google / Android Developers, [Use Jetpack Compose on Android TV](https://developer.android.com/training/tv/playback/compose), updated September 1, 2026; Android, [JetStream Compose sample](https://github.com/android/tv-samples/tree/main/JetStreamCompose). Native TV UI reference.
[^12]: Google / Android Developers, [Compose performance best practices](https://developer.android.com/develop/ui/compose/performance/bestpractices). State computation and lazy-layout keys.
[^13]: Flutter, [Performance best practices](https://docs.flutter.dev/perf/best-practices). Rebuild scope and compositing costs.
[^14]: Flutter, [Use the Performance view](https://docs.flutter.dev/tools/devtools/performance). UI/raster timing and CPU diagnosis.
[^15]: Google / Android Developers, [Slow rendering](https://developer.android.com/topic/performance/vitals/render). Frame budgets and limits of View-based rendering statistics.
