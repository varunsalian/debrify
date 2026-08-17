# Profile isolation suite

Run with:

```
flutter test test/profiles/isolation_suite/
```

Three files, each covering a different way isolation fails. They are additive to
the per-feature isolation tests in `test/profiles/` — those check features
somebody thought of, these try to cover the ones nobody did.

| File | Shape | Answers |
|---|---|---|
| `stale_runtime_guard_test.dart` | source + behavioural | Does anything keep serving profile A after a switch, with no relaunch? |
| `preference_key_sweep_test.dart` | enumerate-then-assert | Does every key that exists belong to a profile or to the device? |
| `live_switch_isolation_test.dart` | end-to-end | Does a real switch through the real participant leave anything behind? |

## The two dimensions

**Data at rest.** Keys and files partitioned by scope. Covered by the key sweep
and by `profile_source_guard_test.dart`.

**Runtime state.** The bytes on disk are partitioned correctly, but something in
memory still holds profile A's value, so profile B sees A's data on screen until
the app is killed. This is the harder class and it has three sub-shapes, all
guarded here:

1. **A cache that never resets** — a service grew a `resetProfileScope` but was
   never wired into `ProfileAppLifecycleParticipant`.
2. **A synchronous mirror** — `StorageService.<name>Cached` is what the UI
   paints from; one left holding A's value is A's screen shown to B.
3. **A value read above the gate** — `ProfileGate` rekeys its child on
   `sessionEpoch`, so everything *below* it is destroyed and rebuilt on a
   switch and cannot go stale. Everything *above* it is never rebuilt, so it
   must subscribe. The theme bug was exactly this.

## Every assertion is mutation-tested

Each guard was verified by reintroducing the bug it describes and confirming the
guard fails. This is not ceremony: the first version of the controller guard
**passed while its bug was reintroduced**, because it string-matched a method
body and `indexOf('warm()')` had latched onto a mention of `warm()` in a comment
sixty lines above the method. It was rewritten to drive the real controllers.

A guard that cannot fail is worse than no guard, because it converts an unknown
risk into a false sense of coverage. If you add a case here, mutate it and watch
it go red before you trust it.

## What this suite does NOT cover

Everything here runs on the Dart VM. That boundary is real and it is not small:

- **Native preference state.** Nine Kotlin files read `FlutterSharedPreferences`
  directly (`MainActivity`, `AndroidTvTorrentPlayerActivity`, both recording
  stores, `DownloadTaskStore`, `SubtitleSettings`, `SubtitleFontManager`,
  `ProfilePrivacyState`), plus the native-only `debrify_pending_recordings` and
  `debrify_permissions` files, plus tvOS `UserDefaults`. None is visible here.
- **The native projection has no reader in tests.** Kotlin consumes profile
  preferences through a sequence-guarded JSON snapshot; nothing consumes it in
  a Dart test, so a stale or malformed projection passes silently.
- **`SharedPreferences` is a `Map` here.** No XML file, no `NSUserDefaults`, no
  size ceiling — and the size ceiling is what caused the tvOS process kill.
- **Migration runs on synthetic data.** The IPTV bug came from real accumulated
  preferences, whose shapes nobody predicted.
- **No real lifecycle.** Process death mid-write, backgrounding, real timing.

The native-only stores are also isolated differently, which any future sweep
must account for: `RecordingTaskStore` and `RecordingScheduleStore` are not
namespaced by key at all. Each entry carries a `profileAuthorizationRevision`
and the store throws `SecurityException` when the projection says authorization
changed. A "every key must be scope-prefixed" assertion would be wrong about
them.

For device coverage, use the dev audit export
(`lib/services/profiles/dev/`, Manage profiles → `{}`), which runs on release
builds and whose findings engine judges what the suite here cannot observe.
