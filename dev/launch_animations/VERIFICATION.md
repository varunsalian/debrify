# External launch animations: implementation and release verification

Updated 2026-09-17. Implementation is present; **release approval remains open**.
No website, payments, DRM or conversion of existing built-in painters is included.

## Implementation

- Bounded dotLottie v1/v2 parser, prepared offline library and atomic index.
- Shared contain-fit player for startup and preview, with isolated parsing,
  decoded-image ownership, authored-frame repainting and local draw-error recovery.
- Import, composition selection, preview/replay, backgrounds, Use and Delete in
  Launch Animation settings. Use requires a completed, successfully painted preview.
- One-second startup load decision, disposal of late results, built-in fallback,
  and the existing sequential reveal/Home handoff.
- Device-local library, profile-local selection, built-in and Look integration,
  conditional deletion cleanup and nonportable selection reset on restore.
- Paired protocol-8 package transfer, selected composition/background metadata,
  receiver import without activation, and animation-specific transport limits.
- Seven original example packages, generator, creator guide and standalone QA app.

## Review iteration 1 — package, storage, profiles and authorization

Reviewed parser expansion, asset resolution, commit ordering, cleanup, startup
loading and profile/remote boundaries. Corrections made:

- Enforce expansion limits during inflation even if ZIP size declarations lie.
- Reject parent/precomposition cycles, missing references and excessive expanded
  layer instances; reject repeaters and dynamic values.
- Revalidate prepared JSON before constructing renderer objects on later loads.
- Use AppStorage's platform-specific location, including the tvOS policy.
- Preserve a corrupt library index and its files until explicit recovery.
- Validate receiver authorization again before import commit; preserve outgoing
  profile authorization throughout streamed transfer.
- Clear imported overrides in merge restores without counting that internal
  cleanup as a setting received from the backup.

## Review iteration 2 — playback, settings and regression behavior

Reviewed controller completion, image lifetime, paint exceptions, selection races,
preview readiness, resizing, warnings and transfer receipts. Corrections made:

- Discard/dispose late startup loads; a timeout never starts a second reveal.
- Catch drawing failures at the painter boundary and restore canvas state; use
  the settled fallback rather than replaying another reveal.
- Gate Use on completed preview and final paint, and display runtime warnings.
- Quantize repaint notifications to the composition's authored frame rate.
- Detach warning callbacks when replacing compositions.
- Count repeated precomposition masks and path vertices against expanded budgets,
  as well as counting their layer instances.
- Keep manual imported choices ahead of older queued built-in/Look writes;
  deleting an unrelated import does not clear the current choice.
- Selecting the already-stored built-in fallback still clears an imported override.
- Reject known unsupported luma mattes and merged paths with export guidance.
- Handle missing Android TV document providers with paired-transfer instructions.
  The emulator has no `OPEN_DOCUMENT`/`CATEGORY_OPENABLE` handler for `*/*`;
  its native picker reports `invalid_format_type`, now covered by a widget test.

## Automated evidence

Affected regression command:

```sh
flutter test test/launch_animation test/launch_ident_registry_test.dart test/remote_reliable_transfer_test.dart test/remote_reliable_router_test.dart test/profiles/profile_preference_portability_test.dart test/profiles/profile_restore_coordinator_test.dart
```

134 tests passed, including the expanded-geometry guard and fourteen AppInitializer
cases (TV/non-TV, immediately ready/timeout-driven Home, onboarding, disposal,
recoverable playback failure, initialization after reveal and built-in playback). Tests cover malformed/over-budget packages, forged
ZIP expansion sizes, missing assets, stored-data revalidation, concurrent imports,
revoked commits, corrupt-index preservation, offline restart, deletion/selection
races, local-only preference policy, restore cleanup, startup timeout/late results,
preview readiness, draw-error containment, interrupted-publication cleanup,
older-receiver rejection, missing-TV-picker guidance and encrypted transfer outcomes.
Initializer tests use the real startup state/controller flow with a lightweight
Home builder, avoiding unrelated network/media/database initialization.

The scoped analyzer passed without issues on changed production services/widgets,
launch tests and the QA entry point. `git diff --check` passed.

An existing `test/theme/app_looks_test.dart` assertion expects every Look key to
be excluded from portability; it fails for `phone_nav_style`. The same failure
was reproduced against HEAD's original appearance-preference implementation.
This unrelated baseline expectation was not changed.

## Build and rendering evidence

| Target/check | Result |
| --- | --- |
| Full macOS app, debug build | Passed |
| macOS QA app, profile | Five packages × three aspect ratios; zero playback errors |
| Android TV ARM64 emulator QA app, profile | Five packages × three aspect ratios; zero playback errors |
| Radial-gradient alpha/inverted-alpha matte example, macOS and Android TV emulator | Three aspect ratios on each; zero playback errors; captures visually checked |
| tvOS QA app, unsigned release build | Passed |
| tvOS simulator link | Blocked: current MoltenVK framework contains only a tvOS device slice |
| Paired physical Apple TV, separate QA bundle | Targeted signing succeeded; QA run interrupted the user and was stopped. No completed playback result. |

Raw profile runs are in `verification/macos-profile.json` and
`verification/android-tv-emulator-profile.json`. The player changes in those runs
match the implementation; the later expanded-budget guard only tightens import
validation. Sample frame captures were inspected, including outlined text and the
gradient/mask example. Original sample playback was also tested at portrait,
16:9 and ultrawide widget dimensions and multiple progress values.

For these small samples, macOS P95 raster times were 0.373–0.931 ms and prepared
loads were 1 ms. Android TV emulator P95 raster times were 1.421–21.312 ms and
prepared loads were 2–5 ms. The 21.312 ms result occurred on the portrait
presentation of the gradient/mask fixture. This emulator result is not a physical
TV benchmark and does not establish consistent 60 fps. No upper-budget stress or
physical low-memory performance claim is made.

The additional matte runs are in `verification/macos-mattes-profile.json` and
`verification/android-tv-mattes-profile.json`, with representative PNG captures
beside them. Their radial gradient and opposite half-word mattes render as
intended. P95 raster times were 0.958–1.174 ms on macOS and 2.396–17.785 ms on
the Android TV emulator. Whole-process RSS was approximately 147–156 MiB and
202–207 MiB respectively; these measurements include the Flutter app and are not
isolated animation allocation figures. The recorder now includes RSS and peak RSS.

Reproduce a profile run with:

```sh
flutter run --profile -d macos -t dev/launch_animations/verify_desktop.dart
# Or substitute the Android TV emulator/device ID for macos.
# To run only the matte fixture, append --dart-define=LAUNCH_SAMPLE=hello-mattes
```

The QA entry point uses embedded original fixtures and temporary storage. It does
not initialize Debrify preferences or its database. It writes screenshots and
`results.json` to the platform's temporary directory, prints the location, and
exits. It is not the production entry point or a production asset bundle.

## Remaining release gates

Do not mark the plan production-ready until these are verified:

- Real phone, lower-powered Android TV and Apple TV: import/paired transfer →
  preview → select → cold launch offline, including remote focus and Back.
- Physical Android TV picker-provider availability; the emulator's missing-provider
  path is now checked, with actionable paired-transfer guidance.
- Full-application cold-start comparison on physical devices. All listed initializer
  control-flow cases now have widget coverage, including initialization after the
  reveal and the built-in path; these are not physical end-to-end evidence.
- Physical-device frame timing, memory, background/foreground and rotation/resize;
  include content approaching the image, path, mask and layer ceilings. Reduce
  published ceilings if lower-powered hardware cannot sustain them.
- Physical paired transfer and remote focus/Back checks. The old-receiver rejection
  now has a sender-level test proving it runs before package access, and transport/
  router tests cover encrypted import, but these are not device UI QA.

Apple TV restriction: the user explicitly prohibited use of their Apple TV
after the QA launch interrupted their viewing. Do not connect to, install on,
launch apps on, or otherwise operate that device without a new explicit go-ahead.
The QA console was interrupted and stopped. Signing was resolved by explicitly
targeting the paired device, but playback verification did not complete. The
simulator still lacks a compatible MoltenVK slice. Continue local/emulator work
only; do not treat general workspace permissions as permission to use the TV.
