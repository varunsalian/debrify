# TV player structural CI guard

Phase 20 adds the unconditional `tvplayer-structure` job in `.github/workflows/checks.yml`. It runs on every configured push (including documentation-only pushes), PR and manual check invocation. Checkout fetches full history; setup-java selects Zulu JDK 21, matching the Android build job. The final-tree p19 command deliberately has no `--at`. Historical manifest checks remain separate evidence.

`dev/tool/kotlin_toolchain.py` is the sole jar lookup for PSI and all eleven compiled-fixture helpers. `GRADLE_USER_HOME` overrides the original `~/.gradle` default; `JAVA_HOME` supplies CI's JDK and the original Android Studio JBR remains the local fallback. `TVPLAYER_EVIDENCE_ROOT` redirects intermediate PSI/fixture evidence. `bootstrap_kotlin_tools.py` downloads all five exact coordinates in `kotlin_artifacts.json` from Maven Central into that one Gradle-cache layout and verifies pinned SHA-256/SHA-1 values. Missing or ambiguous offline artifacts and checksum mismatches fail. The cache action is optional acceleration: bootstrap runs even on a cache hit. No Android SDK, Flutter engine or device is needed for this structural job.

The job runs the full historical/current checker self-test dispatcher, the final-tree p19 manifest check (including earlier destinations), the three compiled Host usage controls, and the boundary guard with its own self-tests. The existing size, format, analyzer and behavior jobs remain. The workflow-wide documentation path filter was removed so the final decision-only gate cannot skip the required structural job.

## Boundary contract

`dev/tool/check_tvplayer_boundaries.py` uses real Kotlin PSI/lexer tokens. The explicit reviewed configuration is `dev/tool/tvplayer_boundaries.json`; the source set must equal the union of p1–p19 destinations. All 63 completed files are checked. The guard checks import-free same-package names, fully qualified references and import aliases, while ignoring comments and string literals. Discovery recursively scans all Kotlin files under `android/app/src/main`. Every file in the TV directory (including nested directories), and every main-source file declaring `package com.debrify.app.tv` regardless of its directory, must be either a completed destination or one of the exact legacy exclusions below; a new unclassified file fails. The declared package comes from Kotlin PSI, so comments and strings do not classify unrelated packages. Test sources and tool fixtures are outside this production-source scope.

- Flutter UI/engine types are forbidden: Flutter Activity/Fragment/FragmentActivity, Engine/EngineGroup/EngineCache, View/TextureView/SurfaceView, Renderer/JNI, DartExecutor and BinaryMessenger. MethodCall, BasicMessageChannel and EventChannel are also forbidden. Every `io.flutter` namespace reference must be the approved `io.flutter.plugin.common.MethodChannel` type (including its Result interface).
- `MainActivity` is allowed only in the 18 exact files listed in the configuration, solely to import it and invoke `getAndroidTvPlayerChannel()`. Other accessors, concrete Activity references or generic engine access are rejected.
- The concrete `AndroidTvTorrentPlayerActivity` may supply only its retained nested `ShufflePlaybackAttempt` and `TvSourceAddon` model types in the exact five files listed in the configuration. Collaborators receive AppCompatActivity for Android context/lifecycle operations.
- There are 41 migrated collaborator implementation types, 27 exact Host interface identities and 59 approved peer-bearing Host member declarations. A peer type may appear only in its own implementation, an approved Host member type or an approved owner/child relationship. Import permission does not permit use outside the approved scope. Adding another Host peer edge fails. Data models, adapters and ordinary Android/platform/service types retain their existing contracts; this guard does not redesign them.
- The following owner/child pairs may name each other because the owner eagerly constructs its collaborator and the child borrows its owner's state/Host. No unrelated sibling edge is permitted.

| Owner | Eager child |
| --- | --- |
| `TvControlsOverlayController` | `TvDockIdentityPresenter` |
| `TvControlsOverlayController` | `TvSeekScrubController` |
| `TvPlaybackStartController` | `TvPlaybackNavigator` |
| `TvIptvTuneController` | `TvIptvTwinTrial` |
| `TvControlsDockController` | `TvLiveDockStyler` |
| `TvSubtitleSourcesController` | `TvSubtitleSearchDialogs` |
| `TvPlaylistOverlayController` | `TvPlaylistFocusNavigator` |
| `TvPlaylistOverlayController` | `TvPlaylistGuideSkin` |
| `TvIptvGuideChromeController` | `TvIptvGuideOverlayBuilder` |
| `TvIptvGuideChromeController` | `TvIptvGuidePickers` |
| `TvIptvGuideController` | `TvIptvZapPager` |
| `TvIptvGuideController` | `TvIptvChannelNavigator` |
| `TvSourceSwitchController` | `TvSourceSwitchApplier` |
| `TvIptvZapBannerController` | `TvIptvZapBannerStyledRenderer` |

The twelve self-tests include the real completed tree, direct same-package and fully qualified peer bypasses, an alias bypass even when importing that peer for a legitimate Host, Flutter types/namespace access, an unapproved MainActivity accessor, an unapproved concrete Activity reference, a new Host peer edge, scope/exclusion widening, harmless comment/string controls, and discovery negatives for a nested peer bypass and an out-of-directory same-package file. The three reference-bypass controls must fail for their stated boundary reason; both discovery controls must fail the exact unclassified-source rule.

## Exact legacy file exclusions

These 38 files predate the extraction or remain the approved Activity composition root/supporting services and UI. They are not blanket exclusions for a directory or filename pattern. The Activity remains covered by the move checker and the 3,776-line shrink-only size ratchet; ShowShuffle is also frozen by its source-bound initializer proof. Legacy dependencies may continue to be borrowed through the existing contracts. Changing this list requires a reviewed scope change; a completed destination cannot be added to it.

- `AndroidTvTorrentPlayerActivity.kt`
- `BadgeArtworkSize.kt`
- `DebrifyTvPlayerStyle.kt`
- `DockFormatTags.kt`
- `IptvDeviceQuirks.kt`
- `IptvGuideStyle.kt`
- `IptvLiveRecovery.kt`
- `IptvRecordingController.kt`
- `IptvTuneDiagnostics.kt`
- `NullableJsonString.kt`
- `PlaybackReturnHandoff.kt`
- `ProtectedStreamHttp.kt`
- `RecordingDataSource.kt`
- `SeekFeedbackManager.kt`
- `ShowShuffle.kt`
- `SkipDbSegmentClient.kt`
- `SourceAddonPresentation.kt`
- `SourceQualityParser.kt`
- `SpeechFeatureTap.kt`
- `StartupFailoverCursor.kt`
- `StreamBadgeSvg.kt`
- `SubtitleAutoSelection.kt`
- `SubtitleControlsLiftController.kt`
- `SubtitleLinePickerController.kt`
- `SubtitlePanelController.kt`
- `SubtitleSyncOverlayController.kt`
- `SwitchedEpisodeTitle.kt`
- `TvControlsSkin.kt`
- `TvDisplayModeController.kt`
- `TvPlaybackRecoveryStore.kt`
- `TvSourceBadgeResult.kt`
- `TvSourceBadgeText.kt`
- `TvSourceBrowserController.kt`
- `TvStreamBadgeStrip.kt`
- `TvTrailerTexturePlayer.kt`
- `UnifiedMenuController.kt`
- `UnifiedMenuSections.kt`
- `VodHttpDataSource.kt`

Local evidence is under `p20/cold/` and `p20/cold-job/`. The exact workflow commands are exercised from an initially empty temporary GRADLE_USER_HOME with the local JDK 21. Actual Linux CI evidence on the pushed final SHA remains pending for Claude; local checks alone do not close that requirement.
