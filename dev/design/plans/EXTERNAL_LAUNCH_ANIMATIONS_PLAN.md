# External launch animations — polished first release

Status: implemented with release verification still in progress, 2026-09-17.
See `dev/launch_animations/VERIFICATION.md` for review findings, completed checks
and the remaining device release gates.

## Outcome and effort

Users import a compatible `.lottie` file, preview it, select it, and see it at
the next app launch. Playback works offline and an invalid or missing file never
prevents entry into the app. This covers the Flutter launch screen.

Target: 15–20 developer working days including integration, device testing and
routine fixes; approximately 3–4 weeks for one developer with test devices
available. The phase estimates use this entire budget, with no extra contingency.
Platform or renderer issues found on devices may extend the schedule.
No separate proof-of-concept phase. Build the production path incrementally.

## Keep the design small

- Add the Flutter `lottie` package as a new dependency, with a small archive
  adapter for dotLottie manifests and assets. Pin the version validated by the
  release; the package is not currently included in Debrify.
- Reuse `archive`, `file_picker`, `path_provider`, preferences, the existing
  Launch Animation page and the existing startup handoff.
- Keep current built-in painters and their IDs. Imported animations use a widget
  player alongside them; do not force widgets into the `CustomPainter` contract
  or rewrite all built-in animations.
- One import/storage service, one imported-animation player shared by preview
  and launch, and small changes to settings and startup should suffice.
- No new database, plugin framework, native renderer port or custom animation
  language. Local metadata can be a versioned JSON index written atomically.

## Supported files and predictable playback

- Read dotLottie v1 and v2 archive layouts and their animation manifests.
  This is a documented playback subset, not support for every dotLottie feature.
- Support ordinary renderer-compatible vector animation and packaged images.
  For reliable custom names, the creator guide requires text converted to paths.
  Publish a compatibility table tied to the pinned renderer, covering shapes,
  transforms, gradients, masks/mattes, packaged images and outlined text. Mark
  each feature supported, limited or unsupported using representative fixtures.
- Do not execute state machines, expressions, scripts, audio or external asset
  requests. Dynamic themes and slots are outside the first-release contract.
  A package containing optional features may still supply an independent,
  compatible animation; explain that those features are not applied.
- Reject malformed/over-budget content, missing required assets, external asset
  dependencies and known unsupported features required by the selected animation
  (including live text/fonts, expressions, audio and dynamic theme/slot values).
  Warn about unused optional package features and non-fatal renderer warnings;
  show those warnings alongside a preview before enabling Use. Parsing alone
  must not label a file visually verified. Keep detection to known feature checks
  and renderer diagnostics, rather than building a universal Lottie validator.
- For a multi-animation file, offer an animation selector at import. Default to
  the manifest's initial animation when supported, otherwise the first declared
  animation. Persist the selected animation ID; do not guess that different
  animations are aspect-ratio variants.
- Play once at authored speed, then hold the last rendered frame while the
  existing home-ready logic finishes. Ignore looping for app launch.
- Initial release limits: 10 MiB compressed, 40 MiB expanded, 256 archive entries,
  5 seconds per selected animation and at most 60 fps. Also bound decoded image
  pixels, nesting and composition complexity; choose and document those budgets
  from representative phone/TV tests before release. These limits bound resource
  use; they do not promise every accepted animation runs at 60 fps.

## Import and storage — 3–4 days

1. Read with a byte limit; validate manifest, animation IDs, JSON, references,
   finite dimensions/timing, supported dependencies and asset budgets.
2. Reject absolute/traversing paths, duplicate ambiguous paths and oversized
   expanded content. Enforce limits while decompressing, not only after decoding.
3. Prepare files in a temporary app-managed directory and parse the selected
   composition. Commit only a successful import; cancellation/failure preserves
   the current selection and removes temporary files.
4. Store using an internally generated identifier. Keep original package bytes
   for transfer and prepared local assets for playback without ZIP extraction at
   every launch. Read only the selected animation at startup, not the whole library.
5. Provide useful failures: damaged package, unsupported content, missing asset,
   file too large, or animation too long. Import does not automatically activate.

Serialize library mutations from local imports, remote transfers and deletion
with one shared lock. Prepare imports outside the lock, then commit their files
before atomically publishing the updated index. On deletion, remove the index
entry before deleting its files. Reconcile abandoned temporary files and orphaned
package directories when opening library settings, under the same lock; exclude
in-progress imports. Do not add a full-library scan to startup.

If the index is damaged, preserve it for diagnosis, use the built-in launch
fallback and show a recoverable library error with a re-import option in settings.
Never derive deletion paths from an unvalidated index. Interrupted writes or
cleanup failures must not stop startup or overwrite another completed import.

## Settings and screens — 3–4 days

- Extend `lib/screens/settings/launch_animation_page.dart` with an Imported
  section and Import, Preview/Replay, Use and Delete actions. Reuse existing
  settings styling and remote focus behavior.
- Preview through the exact same player and layout settings as launch. Provide
  portrait and landscape preview frames so users can judge their own artwork.
- Use centered proportional contain-fit: no stretching or clipping. Offer a
  background color for transparent/letterboxed artwork and persist it per import.
  Fill/crop controls are deferred.
- Respect valid authored background metadata where supported; otherwise use an
  opaque default. Imported artwork retains its own colors; app theme recoloring
  remains a built-in animation option.
- Changing orientation recomputes layout without restarting the animation.
  Validate phone, tablet, desktop/window resizing, ultrawide and 16:9 TV layouts.
- One composition cannot guarantee beautiful edge-to-edge framing on every
  screen. First release guarantees proportional layout; automatic alternate
  composition mapping can be added later without blocking standard file imports.
- Deletion removes the import from the shared device library. Tell the user it
  affects every profile using that file. Clear the active profile's reference
  only if it points to the deleted import; deleting another import preserves
  the current selection. Recheck that match when committing the deletion so a
  concurrent selection change is preserved;
  other profiles resolve their now-missing reference to their built-in fallback
  when loaded. Do not rewrite every profile solely to clean up stale references.

## Startup and preference integration — 3–4 days

- Integrate into `lib/widgets/app_initializer.dart`, preserving onboarding,
  home-ready timeout, loading indicator, TV hidden prepaint and exit behavior.
- Keep the current sequence: initialization and reveal run together, then Home
  mounts and loads after the reveal. The five-second animation limit bounds the
  authored reveal, not total startup time; Home loading can add its existing
  ten-second readiness timeout plus handoff. Document this in the creator guide
  and test the maximum-duration animation with slow Home loading. Moving Home
  loading earlier is deferred to avoid expanding TV startup changes.
- Keep a stable opaque surface while loading local assets. Load in parallel with
  initialization; avoid blocking `runApp` on package parsing. Add a bounded load
  deadline (initially one second), then use the built-in fallback for that launch.
- Move expensive archive/JSON/composition parsing off the UI isolate using the
  renderer's background-loading support where available. Any remaining parsing
  needs bounded work or a worker isolate; a Future timeout cannot interrupt
  synchronous UI-thread work. Verify this on supported Flutter/tvOS builds.
- Choose the initial launch player once. If loading times out, fails, or the widget is
  disposed, cancel work where supported and discard late results using a load
  generation token. A late success must never replace fallback or start a second
  reveal. Dispose unused resources and keep one reveal-completion path.
- Permit a one-way transition from imported playback to fallback for recoverable
  image-decode or rendering errors after loading. Stop and detach the imported
  player, display the built-in fallback's static settled surface and complete
  the reveal wait exactly once; continue initialization/Home readiness normally.
  Do not replay a full fallback reveal or retry the failed animation that launch.
  Handle errors at the player/asset boundary, including errors reported during
  painting; do not assume an asynchronous load error handler catches draw errors.
  Preview failures similarly stop playback, show a useful error and disable Use.
  This recovery does not promise survival of process-level out-of-memory failures.
- Base reveal completion on the selected composition's duration. Retain a
  deadline for playback completion and handle disposal/lifecycle cancellation.
- A fallback must finish through the same startup flow without restarting app
  initialization or leaving an unresolved reveal future.
- Use a device-local installed library with a profile-scoped optional imported
  selection. Leave the current built-in preference as the fallback. Selecting a
  built-in clears the imported override; applying a Look that chooses a launch
  animation must do the same.
- Compare selections by source (built-in/imported) and ID. Selecting the stored
  built-in fallback while an import is active must clear the override rather than
  hit the picker's existing same-ID early return. Both manual selection paths
  notify `LookApplier.noteExternalWrite('launch_animation')`. Serialize relevant
  preference writes and recheck selection generation so an older in-flight Look
  cannot clear a newer imported selection. Keep UI/cache state consistent with
  the winning selection, including persistence failure and profile switching.
- Audit `StorageService`, profile creation/reset/switching, appearance preference
  validation and sync refresh. Explicitly exclude imported-selection IDs and local
  file paths from automatic sync, cross-device backups and profile-graph exports;
  those mechanisms do not carry the animation content. Restoring/replacing a
  profile clears its old imported override. Keep existing built-in preference
  backup behavior. Same-device profile copies may retain a valid imported ID.
- Keep the library on profile reset/removal, clear that profile's selection and
  reload the override on profile switches. A missing file or stale ID always
  resolves to the profile's built-in fallback. Package transfer installs content
  only; the receiver explicitly chooses Use for its active profile.
- Account for tvOS cache eviction: missing assets produce a recoverable selection
  state in settings and a working fallback at launch.

## TV delivery — 2–3 days

- Use file picking on platforms that support it, including testing actual Android
  TV provider availability rather than assuming mobile behavior.
- For devices without a file picker, reuse Debrify's existing paired remote
  transfer transport to send an imported package from another Debrify device.
  Route received bytes through the same limits and import validator.
- Add only an animation transfer payload/action; retain the transport's existing
  pairing, authorization and retries. No separate upload server or website.
- Send the original package with its selected animation ID and optional opaque
  background color as transfer metadata. Validate that the ID exists in the
  received manifest, validate the color and apply the same composition checks
  as local import. Missing metadata uses normal import defaults; invalid supplied
  metadata fails clearly. The receiver previews those choices before explicitly
  selecting Use; transfer never activates an animation automatically.
- Advertise an animation-transfer capability through the existing protocol
  version/capability mechanism. Check it before sending; an older receiver gets
  a clear update-required message and no unsupported payload. Unknown animation
  payloads must fail cleanly without affecting other transfer types.
- Apply the 10 MiB animation-specific limit at the receiving transport boundary:
  reject oversized declared lengths before accepting the body. Preserve the
  transport's mandatory declared length and encrypted-body length checks; reject
  missing or inconsistent lengths and enforce the actual byte budget during
  receipt. Do not add unknown-length transfer support or lower the shared
  transport limit for unrelated transfers. Revalidate the received
  file through the importer and remove partial files on cancellation/failure.
- Validate TV focus, Back behavior, preview and transfer on Android TV and tvOS.
  TV support is not complete until an end-to-end installation path is verified.

## Release verification and documentation — 4–5 days

Automated checks should exercise behavior, not mirror implementation:

- Valid v1/v2, packaged images and multiple animations; malformed archives,
  path traversal, decompression limits and missing/unsupported assets.
- Failed/cancelled imports preserve selection; delete, restart, profile switching
  and missing local content recover correctly.
- Interrupted file/index commits, a damaged index and concurrent local/remote
  imports recover without losing a completed import or blocking startup.
- Shared-library deletion, same-device profile copying, profile reset and
  cross-device backup/restore obey the local selection rules.
- With import A active, deleting import B preserves A; deleting A clears its
  reference and uses the built-in fallback. A selection changed during deletion
  is preserved unless it references the deleted import.
- Animation finishes before/after initialization, slow home readiness, failed
  loading, disposal during startup and onboarding all reach the intended screen.
- A five-second animation followed by slow Home loading respects the documented
  sequential startup policy. Image/decode/draw failure after playback starts
  reaches the static fallback without another reveal or unresolved startup wait.
- Selecting the current built-in fallback clears an imported override; manual
  imported selection wins against an older in-flight Look application.
- Loading timeout followed by late success cannot start another reveal; expensive
  parsing does not block the UI. Compare supported-feature fixtures visually,
  including rejected required features and warnings for unused optional features.
- TV transfer handles older receivers, oversized/misreported lengths, interrupted
  transfers and retries without installing partial files or changing selection.
- Multi-animation transfer preserves the sender's chosen composition/background
  in receiver preview; missing metadata defaults safely and invalid metadata fails.
- Existing launch-registry and affected settings/profile tests stay green.

Run real release/profile-mode checks on a phone, a lower-powered Android TV,
Apple TV and available desktop targets. Check frame timing, memory, cold startup,
rotation/resizing and offline operation. Compare built-in startup before/after;
fix regressions and trim documented content budgets when weaker hardware requires
it. Record platform gaps explicitly instead of claiming untested parity.

Deliver a short app-independent creator guide describing the supported subset,
limits, text outlines, framing and final-frame behavior. Include small original
sample `.lottie` packages for portrait and landscape, plus a multiple-animation
fixture. These are examples for future website exports and other app developers,
not a conversion of the existing animation library.

Ready to release when import → preview → select → cold launch works offline on
the tested targets, TV installation works, failures recover without stranding
startup, and device performance plus the compatibility guide are reviewed.

## Deferred scope

Website, payments, accounts, DRM, catalog/store, cloud animation sync, in-app
animation editing, fill/crop controls, automatic aspect variants, native OS splash customization,
and recreation of the existing built-in animations.

## Format/renderer references

https://dotlottie.io/spec/1.0/
https://dotlottie.io/spec/2.0/
https://pub.dev/packages/lottie
