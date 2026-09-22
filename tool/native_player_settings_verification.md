# Native player settings regression verification

Local verification: 2026-09-22. Base commit: `9e765966` on `0.9.8_alpha`.
Verification covered the working-tree patch based on that commit. Publishing the
patch does not replace the pending Fire TV Cube confirmation below.

## What is fixed

- Refresh the active profile's native settings before each of the three Android
  TV launch methods. Keep publication ordered until Android accepts the launch.
- Recheck profile/session ownership after the last awaited publication step.
- Pass a small, non-secret settings snapshot to both native Activities, and
  reject stale/locked handoffs. Authorization and credentials are NOT cached in
  that snapshot; their existing live checks remain in place.
- Treat settings/profile rejection as a terminal launch error with a retry
  message, not as a reason to fall back to the Flutter player. Normal unsupported
  native-player failures retain their previous fallback behavior.
- Balance a rejected non-trailer launch with a content-playback stop notification
  before releasing its loader, so TV sync and remote polling are not left blocked.
  Trailer rejection must not stop an existing content session.
- In Debrify TV, explicitly disable subtitle tracks when the saved setting is
  Off. Previously an empty preferred language could still permit default or
  forced tracks. Manual subtitle selection can still turn them back on.

No persisted settings format, decoder selection, night-mode audio processing,
or existing live IPTV controls layout was changed.

## Reproduction and test evidence

1. The regression test `a switch during the final write cannot publish old
   player settings` failed before the final scope check was added. It switches
   profiles after advancing the publication sequence but before writing JSON.
2. A native test reproduces the reported defaults signature with an intentionally
   incomplete publication: the old getters return OTT / unset subtitle language /
   night mode 0 despite saved custom values. The new launch rejects that snapshot;
   the Dart launch barrier rebuilds it first.
3. The Activity consumption test failed for Debrify TV's Off setting before the
   explicit track-disable fix. It now verifies the actual track selector,
   night-mode field and style in both players, including manual subtitle re-enable.

These demonstrate real bugs, but the reporter's exact Fire TV Cube trigger is
not yet confirmed. His original version/build number is still needed.

### Automated results

- **227 focused Dart tests passed**, covering projection/lock/privacy, existing
  preference handling and credential recovery, subtitles/audio, native progress,
  TV recovery, watch sync and the new caller-routing guards.
- The rejected-launch widget test reproduced playback remaining active before
  the stop-notification fix, then passed afterward. It exercises public `push`,
  fault-injects the settings rejection after the launch notification, and checks
  stop ordering, exactly-once loader cleanup, idempotence and the retry message.
  A second test ensures trailer rejection does not stop an existing session.
- **221 of 222 native tests passed**, including all 13 new settings tests.
- The sole native failure is
  `TvSourceBrowserFocusTest.dpadAndRailFocusKeepRowsAndImportedArtworkAttached`:
  its fixed child-index lookup cannot find a `TvStreamBadgeStrip`.
  The identical test failed with the identical stack trace in an isolated archive
  of unchanged `9e765966`, proving it predates this patch. It was not modified.
- Focused analysis of the new helper/probe/tests is clean. Analysis of the large
  existing bridge/launcher/TV screen has the same 70 diagnostics as unchanged HEAD;
  there are no new diagnostics or compile errors. `git diff --check` passes.
- Both Android Kotlin and Java production sources compiled successfully.

Logs are in `build/player-settings-review/`: `dart-tests.log`, `native-tests.log`,
`baseline-native-test.log`, `focused-analysis.log`, and the analysis comparison.

### Emulator results

The smoke app uses the existing production bridge methods and native players,
real profile preferences and a synthetic local H.264/AAC MP4. It deliberately
invalidates the native projection before each launch. It does not contact debrid
providers or import user credentials.

The final warm run and cold restart produced **18 passing checks**:

- Movie and episode launches, including repeat launches.
- IPTV live-mode, VOD and episode launches.
- Debrify TV's Torbox and Real-Debrid launch methods.
- Defaults: OTT / automatic subtitle preference / night mode 0.
- Custom profile A: Frost / subtitles Off / night mode 3, with Debrify TV Network.
- Profile B starts with its own defaults, then Classic / Spanish / night mode 1.
- Switching back to A restores A's values.
- All three bridge methods reject locked profiles; a subsequent unlocked launch works.
- After process termination/restart, saved A preferences are restored in the movie
  player and Debrify TV.

All 15 native handoff log records in those two runs match the expected profile
values. Movie, episode and IPTV VOD/episode runs also assert an advancing native
playback checkpoint. Live IPTV and Debrify TV do not provide that same checkpoint
callback; their smoke assertions cover handoff/exit, alongside native Activity
consumption tests. This is not an end-to-end test of any remote provider.

The available emulator is headless and has audio disabled. Computer-use inspection
found no emulator window, so no visual appearance or audible night-mode check is
claimed. The existing live IPTV controls-style override remains unchanged.
Device-specific decoding/audio behavior still needs real hardware verification.

`emulator-smoke.log` contains the latest warm-run PID 9063 and cold-run PID 9529.
The original `com.debrify.app` installation was not replaced or cleared. Testing
used `com.debrify.app.personal`. The probe was stopped and its temporary host HTTP
server and ADB port reverse were removed afterward.

## Repeat the checks

From the project root:

```sh
flutter test --no-pub \
  test/profiles/native_profile_projection_test.dart \
  test/native_player_settings_wiring_test.dart \
  test/video_player_launcher_settings_rejection_test.dart \
  test/main_page_bridge_playback_test.dart \
  test/profiles/profile_lock_privacy_test.dart \
  test/profiles/connection_secret_recovery_test.dart \
  test/profiles/profile_preferences_test.dart \
  test/profiles/subtitle_appearance_preferences_test.dart \
  test/media_server_watch_player_wiring_test.dart \
  test/media_server_watch_sync_test.dart \
  test/subtitle_source_priority_test.dart test/subtitle_edge_style_test.dart \
  test/native_playback_progress_session_test.dart \
  test/tv_playback_recovery_test.dart test/tv_playback_recovery_persistence_test.dart \
  test/player_audio_config_test.dart test/audio_settings_storage_test.dart \
  test/subtitle_no_preference_test.dart test/subtitle_priority_selection_test.dart \
  test/player_auto_next_routing_test.dart

env JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
  ./android/gradlew -p android :app:testDebugUnitTest --console=plain
```

For the isolated emulator probe, serve the synthetic fixture directory on
localhost port 18769 (`python3 -m http.server 18769 --bind 127.0.0.1 --directory
<fixture-directory>`). The expected file is `Debrify Test Movie (2008).mp4`.
Use `adb -s emulator-5554 reverse tcp:18769 tcp:18769`. Then build:

```sh
env JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
  ./android/gradlew -p android :app:assembleDebug \
  -PdebrifyPersonalBuild=true -Ptarget-platform=android-arm64 \
  -Ptarget="$PWD/tool/native_player_settings_smoke.dart"
```

Only install this probe in an isolated emulator where `com.debrify.app.personal`
does not contain real data. It creates synthetic profiles in that app. The first
run checks the full matrix; force-stop/restart the same probe for the saved-profile
cold-start check. Do not distribute the smoke APK as a normal app.

## Fire TV Cube handoff — pending

A separate **normal-app** debug APK (not the smoke entry point) is available at:

`build/player-settings-review/debrify-settings-fix-debug.apk`

It includes ARM32 and ARM64, package `com.debrify.app.personal`, version `0.9.7-settings-review+51`,
and labeled Debrify Personal. It installs separately from the standard app and
does not automatically inherit that app's profiles or settings. If the reporter
already uses Debrify Personal, do not overwrite it without backing up/approval.
This is a local review build, not a published release.

Reporter checklist:

1. Record the affected original app version and Fire TV Cube model/Fire OS version.
2. In the test app, select a visibly different player appearance, subtitles Off,
   and a nonzero night-mode level. Configure only the source needed for testing.
3. Start a movie and an episode. Verify the appearance and the player menu's
   subtitle/night-mode state. Use content with an actual subtitle track.
4. Exit and reopen playback, then restart the app and repeat. Check IPTV and
   Debrify TV if those are part of the original report.
5. Manually turn subtitles on and off in the player to confirm the controls still
   work. If using multiple profiles, verify that switching does not copy settings
   from another profile. Confirm night mode audibly on the Cube's normal audio setup.

Send back pass/fail plus the exact content type/player used. Do not share tokens,
passwords or authenticated stream URLs. No reporter message or upload has been sent.

Completion status: steps 1–4 and the local part of step 5 are verified to the
limits above. Fire TV Cube confirmation remains outstanding; zero regressions or
resolution of the reporter's exact trigger is not asserted.
