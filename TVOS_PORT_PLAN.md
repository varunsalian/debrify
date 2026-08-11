# Debrify on Apple TV — port plan

Status: **Phase A done. Phase B done (app builds AND runs on the tvOS
simulator).** Everything below Phase B is planned, not built.

Written after actually running the app on Apple TV, so the claims here are
observations, not predictions. Where something is still unverified it says so.

---

## 0. What was actually proven

The app **builds and runs on the Apple TV simulator today**, with the real
Home screen: sidebar rail, Cinemeta catalogs fetched over the network, posters
downloaded and cached, onboarding, migrations. That happened with **zero
changes to `lib/`** for the build itself — only pubspec additions.

Verified working on tvOS:

| Thing | Evidence |
|---|---|
| Build (debug, simulator, arm64) | `flutter-tvos build tvos` succeeds |
| Launch + render | screenshots of onboarding and Home |
| `shared_preferences_tvos` | 11 KB prefs plist written; addons persisted |
| `path_provider_tvos` | image cache populated (posters render) |
| Networking (`http`) | Cinemeta catalogs load |
| App migration pipeline | runs, seeds Cinemeta/OpenSubtitles/Watch Next |
| **`sqflite_tvos` + a real `Documents/` dir** | `Documents/debrify_tv.db` created on device container |
| `cached_network_image` | `Library/Application Support/libCachedImageData.db` |

Verified BROKEN on tvOS:

| Thing | Detail |
|---|---|
| `package_info_plus` | No usable tvOS impl → **fixed** (see §1) |
| `app_links` | `MissingPluginException` on `getInitialLink` — deep links are cut anyway |
| `PlatformUtil.isAndroidTvCached` | **Permanently `false`** — see §3, biggest work item |
| `media_kit` | Absent from the tvOS plugin registrant → no playback, no trailers |
| `sqlite3_flutter_libs` | Also absent — see §2, the IPTV catalog DB is untested |

---

## 1. Already fixed in this working tree

**`AppVersionInfo`** (`lib/utils/app_version_info.dart`, new). `package_info_plus`
has no working tvOS implementation — `package_info_plus_tvos` exists but
requires `package_info_plus_platform_interface ^4.1.0`, which **no published
`package_info_plus` uses** (10.2.1 still pins `^3.2.1`), so it cannot resolve
at all. The un-guarded `PackageInfo.fromPlatform()` sat mid-`AppMigrationService`
and its throw **aborted the entire migration run on every tvOS launch**.
Now wrapped, and the migration explicitly skips the version gate (without
writing a bogus "last version") when the platform can't answer. Same wrapper
applied at the other two call sites — `settings_screen.dart` was worse: it was
inside a `Future.wait`, so it would have failed the whole settings load.

`device_info_plus_tvos` is unusable for the identical reason (wants platform
interface `^8.1.0`, plugin ships `^7.x`). Not added; we never call it directly.

**Data point on ecosystem maturity:** of 8 suggested `_tvos` packages, **2 are
unresolvable against their own plugins**, and every one is `0.0.x`.

---

## 2. Dependency status (measured, not guessed)

**Working now:** `connectivity_plus_tvos`, `path_provider_tvos`,
`shared_preferences_tvos`, `sqflite_tvos`, `video_player_tvos`,
`wakelock_plus_tvos` — all added to `pubspec.yaml`.

**Pure Dart, no port needed:** http, youtube_explode_dart, crypto, xml, yaml,
archive, intl, provider, flutter_markdown, google_fonts, collection, path,
sqflite_common_ffi, ffi.

**Unusable / absent:** package_info_plus_tvos, device_info_plus_tvos (§1).

**Cut on tvOS (still to gate):** android_intent_plus, saf_stream,
flutter_sharing_intent, background_downloader, permission_handler,
screen_brightness, volume_controller, file_picker, app_links, window_manager,
url_launcher. They **compile** — they fail at runtime, which is the trap.

**Definitive list of what the tvOS build actually registers** — from the
generated `tvos/Runner/GeneratedPluginRegistrant.m`, six plugins and nothing
else:

```
connectivity_plus_tvos   path_provider_tvos   shared_preferences_tvos
sqflite_tvos             video_player_tvos    wakelock_plus_tvos
```

Every other native plugin — **media_kit included** — is absent from the
registrant entirely. That is why the build succeeds: unsupported plugins are
skipped silently, not errored on. Any call into one throws at runtime.

Operational note found in that same generated file: on a **physical** Apple TV,
debug builds must be launched via `flutter-tvos run` — the debug engine needs an
attached debugger, and plugin registration bails out (loudly) otherwise.

**`sqlite3` / `sqlite3_flutter_libs` — risk RESOLVED by source inspection.**
This is the FFI path behind `iptv_catalog.db` (distinct from `sqflite`, which
is already confirmed working). `sqlite3_flutter_libs` is indeed absent from
the tvOS build — but `package:sqlite3`'s loader degrades on purpose:

```dart
} else if (Platform.isIOS) {          // ← tvOS takes this branch (isIOS is true)
  return _tryLoadingFromSqliteFlutterLibs() ?? DynamicLibrary.process();
}
```

With the bundled libs missing it falls back to `DynamicLibrary.process()`, and
sqlite3 ships inside the Apple SDKs, so the symbols are already in the
process. The IPTV catalog DB should therefore work on tvOS against the
**system** sqlite3.

The only cost is an older engine than the bundled one. That happens to be a
non-issue here: FTS5 was already removed from this codebase precisely because
the bundled and host engines disagreed (`project_iptv_fts_reverted`), so
nothing left depends on a newer sqlite. **Still to confirm at runtime** by
adding an IPTV source, but this is no longer the top risk.

---

## 3. Phase C — platform identity (the biggest real work item)

`PlatformUtil.isAndroidTV()` short-circuits: `if (!Platform.isAndroid) return
false`. On Apple TV that means `isAndroidTvCached` is **always false**, so every
accommodation gated on it is silently off:

- DPAD focus idioms across ~302 `onKeyEvent` handlers
- `TvTextField` / in-app keyboard (correctly off — tvOS has a system keyboard)
- **image-cache memory caps** (a real OOM risk on a 3 GB Apple TV)
- the TV perf gating from the perf playbook

The Home screen renders the wide/desktop layout *by width breakpoint*, which
merely resembles the TV layout.

**Work:** introduce a television concept (`isTelevision`) true for Android TV
**and** tvOS, then audit all **109** `isAndroidTvCached` sites and decide each
one — some mean "is a TV" (keep), some mean "is Android TV specifically"
(e.g. the native-player handoff, which has no tvOS counterpart). A blanket
find-and-replace would be wrong.

Also: `Platform.isIOS` is **`true`** on tvOS (the fork documents this
explicitly). Every `isIOS` branch needs reviewing with `&& !Platform.isTvOS`,
or iPhone-only behaviour silently activates on Apple TV.

## 4. Phase D — storage (risk downgraded — earlier assumption was wrong)

**Correction to the original assessment.** The classic tvOS guidance ("no
Documents directory, 500 KB `NSUserDefaults`, everything else purgeable") comes
from tvOS 9-era documentation. On **tvOS 26.5 the app has a real `Documents/`
directory and sqflite wrote `debrify_tv.db` into it** — observed, not assumed.
So lists/favorites/history are not obviously doomed, and the storage re-architecture
I originally scoped may be unnecessary.

Two caveats keep this an open question rather than a solved one:
- The **simulator's filesystem is more permissive than a real device.** This
  must be re-confirmed on hardware before anyone relies on it.
- The **500 KB `NSUserDefaults` ceiling is still untested.** The prefs plist is
  only 11 KB on a fresh install; a heavy user with many playlists and long
  history is the case that matters. `StorageService` is 6,176 lines with 110
  `setString` calls, so it is prefs-heavy by design.

Plan (contingent): if the ceiling bites, move large blobs (watch history,
resume, playlists) to sqlite — which now looks viable — and keep catalogs as
re-ingestable cache with the existing phone-import as purge recovery.

## 5. Phase E — player — SPIKED 2026-08-03, findings below

A spike was run against the real packages. Everything here is measured.

### E.1 libmpv for Apple TV — EXISTS

- media_kit's own source (`media-kit/libmpv-darwin-build`) targets **ios,
  iossimulator, macos only** — no tvOS, none planned. Dead end.
- **`karelrooted/libmpv` v0.0.1-beta publishes prebuilt xcframeworks with
  `tvos-arm64` AND `tvos-arm64_x86_64-simulator` slices.** Verified by
  inspecting `Libmpv.xcframework/Info.plist`.
- Symbols confirmed present in the tvOS arm64 slice via `nm`: `mpv_create`,
  `mpv_initialize`, `mpv_command`, `mpv_set_option`, `mpv_wait_event`, and
  **`mpv_render_context_create`** (the render API video needs).
- `MPV_CLIENT_API_VERSION` = **2.2** (mpv 0.37-era) — compatible with
  media_kit's generated bindings.
- Caveat: build is dated Dec 2023, and the set is ~800 MB across 29
  frameworks (ffmpeg + libplacebo + libass + luajit are all required —
  confirmed from libmpv's undefined symbols).

### E.2 Two real obstacles the spike surfaced

**(a) The tvOS builds are STATIC (`libmpv.a`), not dynamic frameworks.**
media_kit's `NativeLibrary` only ever calls `DynamicLibrary.open(path)` —
there is no `DynamicLibrary.process()` path. With a static library the symbols
land in the app executable, so `open()` on a `Libmpv.framework/Libmpv` that
doesn't exist will fail. Two ways out: pass
`Platform.resolvedExecutable` as the `libmpv:` path (dlopen'ing the main
executable is equivalent to `.process()`), or patch media_kit. The former
needs **no fork** and is what the spike tests.

**(b) Static linking strips everything.** Nothing in the app references an
`mpv_*` symbol at link time — dart:ffi resolves at runtime — so the linker
discards every object file in `libmpv.a`. Requires `-force_load` on the
archive, applied to the **user** target (it links the executable), per-SDK
because the slice path differs between device and simulator.

### E.3 media_kit's loader has no `tvos` key — but it doesn't matter
`NativeLibrary`'s name map covers windows/linux/macos/ios/android. On tvOS
`Platform.operatingSystem` is `"tvos"`, so the automatic lookup finds nothing
and throws "Unsupported operating system". **However**
`MediaKit.ensureInitialized(libmpv: <path>)` bypasses the map entirely, and
its dispatch branches on `UniversalPlatform.isIOS` — which is **true on tvOS**.
So an explicit path is a one-line app-side fix, not a fork.

### E.4 The renderer ports clean — better than expected
`flutter-tvos plugin port --from-pub media_kit_video` produced a complete
`media_kit_video_tvos`: **5 methods ported as-is, 0 stubbed, 0 imports
removed, 0 manual-review items**, verdict "expected to compile". The
OpenGL ES files (`TextureHW.swift`, `OpenGLESHelpers.swift`,
`TextureGLESContext.swift`) carried over untouched.

This is consistent with the SDK: **tvOS 26.5 ships `OpenGLES.framework`**
(ES1/ES2/ES3 headers) and `CVOpenGLESTextureCache` in CoreVideo — the two
things the hardware texture path needs. The fork's "Metal-only, no OpenGL"
constraint is about **Flutter's engine renderer**, not a ban on the app using
GLES internally to fill a `CVPixelBuffer`; the `FlutterTexture` protocol takes
a pixel buffer and is renderer-agnostic.

Note the porter pulled `media_kit_video` **2.0.1** while the app is on 1.3.x —
a real port should pin the matching version.

### E.5 Original notes (still valid)
`media_kit` has no tvOS support. libmpv **does** build for tvOS
([MPVKit](https://github.com/cxfksword/MPVKit), tvOS 17+, Metal — matches the
fork's Metal-only engine). Work = build the xcframework + patch
`media_kit_libs_video`/`media_kit_video` podspecs + texture path.

`video_player` is a **dead dependency** (nothing in `lib/` imports it), so
"interim AVPlayer" means writing a second player against a different API for a
10,434-line screen — not a shortcut. Recommend going straight to media_kit.
Note `trailer_engine.dart` also uses media_kit: no player ⇒ no trailers.

## 6. Phase F — input (needs hardware, cannot be simulated)
The simulator's remote is keyboard arrows — clean discrete events, i.e. the
*Android TV* model. It will make DPAD look perfect and tell you nothing about
the Siri Remote clickpad. Unanswerable without an Apple TV:
1. Which key does the click send? (`isActivateKey` is one helper — one edit)
2. Does press-and-hold give separated down/up 500 ms apart? (33 `KeyUpEvent` sites)
3. What does Menu map to? (54 `goBack` sites)
4. How many direction events does one swipe generate?

## 7. How to reproduce this build

```sh
export PATH="$PATH:$HOME/flutter-sdks/flutter-tvos/bin"
flutter-tvos build tvos --debug --simulator
xcrun simctl boot 850D871B-E1FC-404A-8DC1-0B2718B64FEC     # Apple TV 4K (3rd gen)
xcrun simctl install 850D871B-E1FC-404A-8DC1-0B2718B64FEC \
    build/tvos/Debug-appletvsimulator/Runner.app
xcrun simctl launch  850D871B-E1FC-404A-8DC1-0B2718B64FEC com.varunsalian
```

Bundle id is `com.varunsalian` (the scaffold used the `--org` value directly);
worth renaming to `com.varunsalian.debrify` for consistency with iOS/Android.

Runtime logs:
`xcrun simctl spawn <device> log show --predicate 'process == "Runner"' --last 5m --style compact`

## 8. Realistic remaining effort

Phases A and B are done. The rest is unchanged from the original estimate
except Phase D, which got cheaper:

| Phase | Estimate | Confidence |
|---|---|---|
| C — platform identity (109 sites) | 1–2 weeks | high |
| D — storage (contingent) | 0–1 week | medium (was 1–2) |
| E — media_kit on tvOS | 2–4 weeks | **low** — the real unknown |
| F — Siri Remote input | 1 week + hardware | low without a device |

**~4–8 weeks** of remaining work, dominated by Phase E.

## 9. Risks
- **Fork dependency.** Engine artifacts, one maintainer, `0.0.x` plugins.
- **No native TV player.** Android TV's Kotlin player has no tvOS counterpart;
  tvOS is Dart-player-only.
- **Distribution** — explicitly out of scope per the user.
