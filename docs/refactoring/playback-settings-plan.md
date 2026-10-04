# Playback settings page refactor — plan

Written 2026-10-04 on `refactor/codebase` (facts verified at `ec997117`; the
page is unchanged since `47169f6e`). Follow [AGENTS.md](../../AGENTS.md).
Revised 2026-10-04 after Codex design review round 1 (nine findings).
Read `pikpak-files-plan.md`, `debrid-downloads-plan.md`,
`torbox-downloads-plan.md` and `iptv-settings-plan.md` first, including
their Progress sections. Read `settings-screen-plan.md` for the settings
conventions.

This plan reuses their technique, checker, tooling, staging and gate
procedure, and only states what differs. The reused parts are:
- callback identity checks;
- tree-recording evidence;
- real-config fixtures;
- original-code worktree proofs;
- the wiring checklist;
- Linux goldens captured from the original code;
- `analyzer_allowlist.txt`.

Execution runs in its own git worktree, on a branch cut from
`refactor/codebase`, in parallel with other refactors. Claude integrates
it. Commit after every step and never push. Gate commits contain `gate`.

Remote CI is pending until Claude pushes, so every step must pass the local
CI-equivalent checks. Claude captures the Linux goldens in a local
`linux/amd64` Docker image with Flutter 3.44.8. The image is calibrated
first: it must reproduce the committed Debrid Linux originals byte for byte.

## Goal

`lib/screens/settings/external_player_settings_page.dart` is 4,289 lines and
isn't dart-formatted. It holds the four Settings → Playback categories:
player, video, audio and subtitles (`PlaybackSettingsSection`). They live
in one widget and one State, `_ExternalPlayerSettingsPageState` (51–4289).

The State holds:
- 133 fields, 3 `static const` lists and 4 getters;
- the default-player mode;
- the external-player choice for macOS, iOS/tvOS, Linux and Windows:
  detection, custom app, command and scheme;
- DeoVR on Android;
- 33 instant-save setters: 4 DeoVR, 23 other settings, and 6 subtitle
  appearance/font setters;
- custom subtitle fonts;
- four platform tile builders and three generic row builders;
- the section builders.

`_externalPlayerSettings` (3260–4210) alone is **951 lines**, over the 800
ceiling.

Split the file into a new feature, `lib/features/playback_settings/`,
**moving code verbatim**. The public widget stays in the facade, at the
file's current path.

**Why a new feature, not `lib/features/settings/`:**
- The settings checker rglobs that folder and rejects unregistered
  declarations (`check_settings_moves.py:674–707`).
- `SETTINGS_COMPLETE = True` rejects `TEMP(settings)`
  (`check_search_architecture.py:25`).
- The settings plan excluded the `lib/screens/settings/` pages.

The page imports nothing from `lib/features/settings`. Two files stay where
they are: `playback_settings_section.dart` and `playback_settings_page.dart`
(the hub). **Out of scope:** the services and storage the page calls. So are
the two player helpers it only reads,
`lib/screens/video_player/services/network_tuning.dart` and
`subtitle_settings_service.dart`; both stay byte-identical.

**Architectural status:** a bounded legacy-extraction stage. Each temporary
exception has an exit milestone:
- **State-driven sections instead of Riverpod.** Exit: Riverpod notifiers
  for playback settings.
- **The `legacy_playback_settings/` bridge,** which calls storage, services,
  `FilePicker` and `Platform` directly. Exit: data contracts for
  preferences, detection and fonts, plus a platform-capability adapter.
- **About 50 scattered `Platform.*`/`PlatformUtil.*` checks.** Exit: the
  same adapter.
- **A facade cap above 400 lines,** only if step 0 measures one (Technique
  2). Exit: under Riverpod, the focus-owner groups own their listeners and
  disposal.
- **Unchanged legacy English text,** including the `$e` snackbars. Exit:
  the app-wide localization migration.

## Public surface

```dart
/// One category inside Settings → Playback. Keeps the existing storage and
/// platform-specific controls shared across the four destinations.
class ExternalPlayerSettingsPage extends StatefulWidget {
  final PlaybackSettingsSection section;

  const ExternalPlayerSettingsPage({
    super.key,
    this.section = PlaybackSettingsSection.player,
  });

  @override
  State<ExternalPlayerSettingsPage> createState() =>
      _ExternalPlayerSettingsPageState();
}
```

This is kept exactly, including the doc comment and field order. It is the
only public symbol. These callers must compile unchanged:
- `playback_settings_page.dart:73`;
- `settings_page_navigation.dart:79–92` (classic, TV Spotlight,
  `settings_tv_layout.dart` and the search leaves);
- the self-push at 2227;
- `test/playback_settings_navigation_test.dart`, which reads `.section` and
  keys each page with `ValueKey(section)`.

## What it contains (line numbers at `ec997117`, unformatted; the step 0 manifest, taken after formatting, is authoritative)

| Lines | Area |
| --- | --- |
| 1–49 | 33 imports; the widget |
| 51–219 | 133 fields (no `late`; 121 have declaration initializers, and 12 nullable `String?` fields rely on implicit null: the three macOS custom fields, `_commandError`, `_iosCustomScheme`, `_iosSchemeError`, `_linuxCustomCommand`, `_linuxCommandError`, `_windowsCustomCommand`, `_windowsCommandError`, `_defaultSubtitleLanguage`, `_defaultAudioLanguage`) |
| 221–447, 449–495 | `initState` (analytics, unawaited `_loadSettings()`, 36 focus listeners); `dispose` (42 disposals, then `super.dispose()`) |
| 497–743 | `_loadSettings` (247 lines) |
| 745–1121 | Mode setter; macOS, iOS/tvOS, Linux and Windows actions (select, browse, save, clear) |
| 1123–1309 | 33 setters: 4 DeoVR, 23 other settings, 6 subtitle appearance/font; the completion-threshold getter and index |
| 1311–1400 | `_loadFonts`, `_importCustomFont`, `_removeCustomFont` |
| 1402–1522 | `_aspectLabels`; the `static const` lists `_nightModeLabels`, `_subtitleLanguageOptions` (51) and `_audioLanguageOptions` (21); the index getters |
| 1524–1773 | Four platform tile builders, holding all four `app.shape.br(10)` calls |
| 1775–2224 | `_buildPlayerModeOption`; the generic `_buildDropdownSetting`, `_buildCheckboxTile` and `_buildSettingDropdown`; `_defaultsCard`, which uses the State's `context` |
| 2226–2229 | `_openPlayerSettings` (the self-push) |
| 2231–3258 | `_playerAppearance`; `_playerSettings` (255); `_videoSettings` (153); `_audioSettings` (113); `_nightModeSettings` (148); `_subtitleSettings` (312) |
| 3260–4210 | `_externalPlayerSettings`: one list literal of 15 collection-`if` elements, E1–E15 |
| 4212–4288 | `build` |

## Contracts that must not change

1. **Section routing.** `build` keeps its order:
   1. the unsupported-platform scaffold;
   2. the `_loading` spinner;
   3. `SettingsPageScaffold`, with `_contentFocusNode` around the column.

   Within the scaffold, `managedExternally` (`section != player &&
   _defaultPlayerMode != 'debrify'`) shows the DeoVR or external banner and
   the "Choose player" tile. Otherwise `switch (section)` picks one of the
   four builders. No `didUpdateWidget` is added.
2. **Lifecycle.** `initState` and `dispose` stay verbatim in the State, with
   receiver-only qualification.
   - `initState` runs: `super.initState()`;
     `AnalyticsService.screenView('playback_${widget.section.name}_settings')`;
     the unawaited `_loadSettings()` (its first `setState` runs inside
     `initState`); then the 36 anonymous listeners, in order.
   - `dispose` runs the 42 disposals in exact order, then
     `super.dispose()`.

   Nothing is added to either method, and neither is split.
3. **Load.** `_loadSettings` keeps:
   - its read order;
   - `needsExternalPlayers`, true only for the Player section;
   - for each platform: detection, then the preferred, custom and command
     reads, then `if (!mounted) return;` and the controller `.text` write
     (524, 538, 553, 568);
   - the Android-only DeoVR reads;
   - `AndroidNativeDownloader.isTelevision()` inside its try/catch, which
     chooses the aspect key;
   - `SubtitleSettingsService.instance.loadAll()` as the last read;
   - one publishing `setState`, with the `NetworkTuning` and skip-provider
     fallbacks;
   - the unawaited `_loadFonts()`;
   - the TV post-frame entry focus: `mounted`; return if a concrete
     non-scope node already has focus; otherwise focus the first
     `traversalDescendants` node;
   - the catch path: `mounted`, `setState`, `if (mounted)`, snackbar.
4. **Writes on open.** Opening any section, on any host, can write
   preferences. Both write paths live in out-of-scope storage/services and
   must still be triggered at the same point and in the same order.
   - **Renderer migration (first).** `_loadSettings` calls
     `PlayerSettingsStorage.getAndroidVideoRendererMode()`
     **unconditionally** (619, before `loadAll`), not only on Android or
     Video. That one awaited page call
     (`player_settings_storage.dart:154–173`) can make **two** storage
     writes, in order: `android_video_renderer_mode` =
     `'direct_mediacodec'`, when the stored mode is absent or the legacy
     `'direct_surface'`, then `android_video_renderer_gpu_migration_v1` =
     `true`. An explicit `'automatic'` or `'direct_mediacodec'` without
     the flag only gains the flag. Once the flag is set, nothing is
     written.
   - **Subtitle migration (last read).** The chain is `loadAll` →
     `_ensurePrefs` → `_adoptExtremeBottomDefault`
     (`subtitle_settings_service.dart:210–230`). It can write
     `subtitle_elevation_index` and
     `subtitle_extreme_bottom_default_adopted_v1` once per profile.
5. **Detection.** The page calls these detectors; the services aren't
   touched. Each call site, its arguments, and its order relative to the
   reads stay as they are.

   | Platform | Detector | Mechanism |
   | --- | --- | --- |
   | macOS | `ExternalPlayerService.detectInstalledPlayers` | `Process.run` `which`, plus app checks |
   | iOS, tvOS | `detectInstalledIOSPlayers` | `canLaunchUrl`; on tvOS, `MethodChannel('debrify/tvurl')` `canOpen` |
   | Linux, Windows | the extension detectors | `which` and `where` |
6. **External player actions** save first, then call `setState`. Each one
   keeps its storage calls, in order:
   - `external_player_preferred` and its `ios_`, `linux_` and `windows_`
     variants, with the values `storageKey`, `'custom_app'`,
     `'custom_command'`, `'custom_scheme'`, `'system_default'` or `'vlc'`;
   - `external_player_custom_path`, `external_player_custom_name` and
     `external_player_custom_command`;
   - `ios_custom_scheme_template`, `linux_custom_command` and
     `windows_custom_command`.

   A null value removes the key. Also kept as they are:
   - the validators and error fields;
   - `.clear()`;
   - the **unconfirmed** clears, which reset a custom preferred player;
   - the macOS picker `pickFiles(type: FileType.custom, allowedExtensions:
     ['app'], dialogTitle: 'Select Video Player Application')`, with its
     app-name derivation and the path, name and preferred writes in order;
   - the snackbar texts, including `$e`.
7. **Instant-save setters.** This covers the 33 setters at 1124–1309: 4
   DeoVR, 23 other settings, and 6 subtitle appearance/font (size, style,
   colour, background, font index, bold). The mode setter (745) is
   separate and belongs to contract 6. Each setter calls `setState`
   **before** its single await, has no try/catch, and returns a Future that
   callers drop. A single awaited call is not a single write: the renderer
   setter's one call writes `android_video_renderer_mode` and then
   `android_video_renderer_gpu_migration_v1` = `true`.

   | Group | Keys |
   | --- | --- |
   | DeoVR | `quick_play_vr_default_screen_type`, `quick_play_vr_default_stereo_mode`, `quick_play_vr_auto_detect_format`, `quick_play_vr_show_dialog` |
   | Player | `player_default_aspect_index` (`player_default_aspect_index_tv` when `_isAndroidTv`), `player_night_mode_index`, `player_system_audio_effects`, `tvos_force_software_decode`, `tvos_force_stereo_audio_v1`, `tvos_legacy_audio_output_v1`, `player_audio_passthrough`, `player_apple_multichannel_audio`, `android_video_renderer_mode` then `android_video_renderer_gpu_migration_v1`, `player_start_portrait` |
   | Network | `content_display_match_mode`, `iptv_decoder_mode`, `network_connect_patience`, `network_buffer_size` |
   | Subtitles | `subtitle_only_foreign_audio`, `subtitle_forced_only`, `subtitle_auto_sync_enabled`, `player_default_subtitle_language`, `player_default_audio_language`, `subtitle_size_index`, `subtitle_style_index`, `subtitle_color_index`, `subtitle_bg_index`, `subtitle_bold`, `subtitle_selected_font_id` |
   | Completion and skip | `movie_completion_threshold`, `episode_completion_threshold`, `skip_segments_enabled`, `skip_segment_provider` |
8. **Scope.** Every key above, plus `default_player_mode` and the external
   player keys, is **profile-owned**. `ProfilePreferences.instance()`
   captures the scope on each call.

   Only `subtitle_custom_fonts` (`DevicePreferences`) and the font files are
   **device-wide**. Native projection and portability stay in storage. No
   scoping is added or removed.

   **Profile handoff is a route pop, not a remount.** `MaterialApp`'s root
   Navigator sits *above* `ProfileGate` (`main.dart:1285`, `home:
   ProfileGate(child: AppInitializer())`). The gate's epoch
   `KeyedSubtree` (`profile_gate.dart:590`) remounts only its child.
   `pushSettingsPage` pushes onto that root Navigator, outside the keyed
   child, so a pushed playback page is never remounted. Instead, every
   picker entry runs `_openPicker`, which pops every route above the
   gate's own route by identity (`popUntil(identical(route, own))`,
   `profile_gate.dart:360`) **before** it locks, clears session state and
   shows the picker. The page is therefore disposed by that pop, but the
   pop doesn't cancel asynchronous work. `ProfilePreferences.instance()`
   captures its scope only **after** awaiting `SharedPreferences`
   (`profile_preferences.dart:275`), so a write already issued can finish
   after the pop, a later write can hit a stale-session rejection, and a
   pending picker result can resume its three separately scoped storage
   calls (page 788) after the switch. These are retained legacy hazards
   (see "Found, not fixed"); the extraction keeps them exactly and adds
   nothing.
9. **Fonts.**
   - **Import:** `pickFiles(type: FileType.any, allowMultiple: false)`; the
     extension rule (`.ttf`, `.otf` or none); the null-path message;
     `importCustomFont(path, name)`; the awaited `_loadFonts()`; three
     messages.
   - **Remove:** `removeCustomFont(font.id)` **deletes a device-wide file,
     with no confirmation and no try/catch**. It resets the selection if
     the removed font was selected, then runs `_loadFonts()` and shows a
     snackbar.
10. **Navigation.** `pushSettingsPage` opens these pages, each behind its
    existing gate: `TvPlayerControlsStylePage` or `PlayerDockPage`,
    `DebrifyTvPlayerStylePage`, `PlayerGuideStylePage`,
    `PlayLoaderStylePage` and `SubtitlePriorityPage`.

    **The self-push stays in the facade State.** `_openPlayerSettings`
    pushes `const ExternalPlayerSettingsPage()`, then runs `if (mounted)
    await _loadSettings();`. Wiring passes its tear-off to the layout.
11. **D-pad and focus.**
    - Entry seeding works as in contract 3.
    - **Mode rows** keep the single-focus-stop idiom: a
      `Focus(canRequestFocus: false, skipTraversal: true)` observer, an
      `InkWell` with `canRequestFocus: !disabled`, and `ExcludeFocus(Radio)`.
      Only the first row has a node.
    - **Night-mode rows** use the same idiom, plus the observer's
      `onKeyEvent`: `isActivateKey` on KeyDown calls `_setNightModeIndex`.
      It is the only `onKeyEvent` in the file.
    - **Three separate `Shortcuts`/`Actions` copies** send up and down
      through `focusInDirection`, **without wrapping**. The checkbox is
      wrapped in `ExcludeFocus(Checkbox)`.
    - **Four `TvTextField`s,** each with `shellRing: false` and an owned
      node. Only macOS passes `onUpArrow`/`onDownArrow`.
    - **Never set `node.onKeyEvent` on a `TvTextField` node.** Add no raw
      `TextField(`.
    - The 36 focused flags (28 built-in and 4 DeoVR ring flags, plus the 4
      external text-field flags `_commandFocused`, `_iosSchemeFocused`,
      `_linuxCommandFocused` and `_windowsCommandFocused`), the "snap,
      don't tween" decorations and the debug label
      `playback-settings-content` stay unchanged.
12. **Callback forms.** These 35 method tear-offs are passed as callbacks:
    2350, 2386, 2398, 2436, 2446, 2495, 2505, 2559, 2606, 2638, 2674, 2716,
    2733, 2751, 2772, 2787, 2991, 3005, 3023, 3129, 3386, 3395, 3571, 3580,
    3755, 3764, 3935, 3945, 4038, 4047, 4160, 4172, 4186, 4195, 4270.
    - Each stays a tear-off of the same member on the same owning instance.
    - Every closure site stays a closure.
    - The `Function(String|bool|int)` parameter types stay.
13. **Platform branches.** Every `Platform.*` and `PlatformUtil.*` predicate
    keeps its site and operands. The branch order stays:
    1. E1, Android info;
    2. E2–E4, iOS/tvOS;
    3. E5–E7, Linux;
    4. E8–E10, Windows;
    5. E11–E14, macOS;
    6. E15, DeoVR.

    The two "TV" truths stay distinct: the asynchronous `_isAndroidTv`
    versus the synchronous `PlatformUtil.isTelevision` and `isTvOS`. The
    unreachable unsupported branch stays.

    **Host reachability.** `_isAndroidTv` is set only inside `if
    (Platform.isAndroid)` (586–592), and no debug flag makes
    `Platform.isAndroid` true, so on macOS and Linux it is always false.
    `debugSetAndroidTvCached(true)` flips `PlatformUtil.isTelevision`
    only. Simulated tvOS (`debugSetTvOS(true)`) on a desktop host keeps
    `Platform.isMacOS`/`isLinux` and `PlatformUtil.isDesktop` true
    alongside `isTvOS`: on macOS, load runs macOS detection and then iOS
    detection, and in `external` mode both E2–E4 and E11–E14 render.
14. **Read-only player helpers** are used exactly as now:
    - `NetworkTuning.standard`, `patienceOptions` and `bufferOptions`;
    - the `SubtitleSize`/`Style`/`Color`/`Background.options` lists;
    - the preview's `SubtitleSettingsData(...).buildTextStyle(fontSizePx:)`
      (3230–3247).

## Destination layout

`lib/features/playback_settings/` has these parts:
- **No `application/` or `models/`.** `_completionThresholdOptions` reads
  storage, and the label getters read State. The three `static const` lists
  move verbatim as statics of the bridge section that uses them; they don't
  become top-level declarations.
- **`presentation/`, outside the bridge:** the three generic row builders,
  as public functions. This holds only if the dependency report confirms
  that they read nothing but their parameters and `Theme`/`AppThemeScope`.
  Their `Shortcuts` copies stay separate.
- **`presentation/legacy_playback_settings/`:** the bridge, with its exact
  prefix in the guard. It holds:
  - the owners;
  - load, the actions, setters and fonts;
  - the tile builders and the mode option;
  - the section builders and the partition;
  - the layout.
- **The facade** keeps:
  - the widget;
  - the owner handles;
  - the verbatim `initState`/`dispose`;
  - `_openPlayerSettings`;
  - the `build` and accessor forwarders;
  - the wiring.

The checker uses `dev/tool/playback_settings_manifest.tsv` and
`playback_settings_checker_config.json`. Evidence goes to
`refactor-evidence/playback_settings/` in the common git directory.

**Guard rules (from step 1):**
- `playback_settings` joins `FEATURES`, with
  `PLAYBACK_SETTINGS_COMPLETE`;
- the exact bridge prefix;
- no service imports in `application/` or anywhere outside the bridge;
- 500-line caps;
- no back-imports of the facade;
- no imports in either direction between this feature and `settings`, or
  `iptv_settings` once it is registered, except their `models/`.

The facade cap and `TEMP(playback_settings)` rejection turn on at step 7.

## Technique (differences only)

1. **Format first.** The file isn't formatted, and CI doesn't cover it.
   Step 0 makes one **format-only commit**, before any characterization: it
   runs `dart format` on this file alone, taking it from 4,289 to **4,314**
   lines.

   The tall style is **not token-identical** here:
   - it adds **9 trailing commas** to single-argument
     `setPreferred…ExternalPlayer(…)` calls (762–1074);
   - it removes **1**, at `_videoSettings`'s `_defaultsCard` call (2680).

   The commit must prove:
   - AST equality;
   - token equality, apart from exactly those 10 formatter-owned commas
     listed by position;
   - an unchanged comment multiset;
   - 20 radii and 4 token calls, before and after;
   - analyzer identities unchanged after relocation;
   - the 6 existing tests passing.

   The size ratchet gets a visible manual raise. This commit is the
   **original** for the checker, characterization, the goldens and the
   Linux capture. After it, the destinations and the facade are formatted
   normally. The checker's AST-identified trailing-comma normalization
   (from the settings plan) absorbs comma changes at new indentation.
2. **Lifecycle stays verbatim and whole.** The step 0 report simulates the
   final facade:
   - the formatted lifecycle with the chosen handles;
   - the widget, imports, handles and composition getter;
   - `_openPlayerSettings` and the forwarders.

   With a 14-character handle, the qualified listeners and disposals wrap.
   The lifecycle alone then measures **≈306 lines** (275 unqualified), so
   the facade will be about 390–420 lines. Use the shortest descriptive
   handles, and make sure none collides with any of the 133 field names
   (Debrid hit exactly that).

   If the facade measures over 400 lines, that measurement becomes its cap,
   rounded up and at most 440, with the exception and exit milestone above.
   Lifecycle code never moves out of the facade to meet the cap.
3. **Partition.** `_externalPlayerSettings` splits at whole collection-`if`
   elements, kept in their original order. The joining method keeps only preamble locals used by E1/the join,
   and E1 inline. E1/the join use neither theme nor t. It then spreads one piece per platform, in branch
   order:
   - iOS/tvOS, E2–E4 (≈186 lines);
   - Linux, E5–E7 (≈183);
   - Windows, E8–E10 (≈183);
   - macOS, E11–E14 (≈282);
   - DeoVR, E15 (≈98).

   A piece repeats the `theme` and `t` locals only where it uses them. E3,
   E6 and E9 are never merged. `_playerSettings` and `_subtitleSettings`
   move whole.

   **The existing partition check cannot express this join.**
   `check_partition` in `check_settings_moves.py` requires the slices to
   start at element 0 and cover every original element (582–596), and it
   requires the dispatcher to be exactly a fresh `final b = Builder(…)`
   followed only by ordered `...b.slice()` spreads (623–655). It has no way
   to represent used join locals, an inline E1, or repeated locals in
   the pieces. Step 0 therefore adds an explicit **configuration-scoped
   extension**, enabled only by keys in
   `playback_settings_checker_config.json`. It must:
   - leave every existing config's behaviour unchanged, proved by all
     existing manifests and self-tests passing unmodified;
   - accept a join method that keeps only original preamble locals used by
     E1/the join (none here), with E1 inline, then spreads exactly the five pieces in branch order;
   - map each piece to its exact original element range (E2–E4, E5–E7,
     E8–E10, E11–E14, E15) and compare the joined elements token for token
     with the original, after the existing comma normalization;
   - permit a piece to repeat the original `theme`/`t` declarations
     verbatim, and only those, and only where the piece uses them;
   - pass a **positive fixture** built from the real config and the actual
     planned join;
   - reject negatives for a reordered piece, an omitted element or piece, a
     duplicated element or piece, an element split across pieces, a changed
     inline E1 or preamble, and an unpermitted extra local.
4. **Owners by group.** Rules:
   - at most 30 fields per owner;
   - every declaration initializer stays at its declaration, and the 12
     implicit-null fields stay without one (no `= null` is added);
   - orphan field and group comments move beside their fields, checked by a
     comment multiset.

   Membership is frozen here (4 + 30 + 12 + 19 + 12 + 56 = 133); the step
   0 report records the exact field lists and handles, and the checker
   rejects any field outside its owner:
   - **core (4):** `_loading`, `_defaultPlayerMode`, `_contentFocusNode`,
     `_firstModeFocusNode`;
   - **external platforms (30), one owner each:** macOS (9: selected,
     installed, custom path, name and command, controller, node, focused
     flag, error), iOS (7), Linux (7), Windows (7), each with its
     controller, node, focused flag and error;
   - **DeoVR (12):** 4 values, 4 nodes and 4 flags;
   - **playback values (19):** `_isAndroidTv`, aspect, night mode, system
     audio effects, the three tvOS values, passthrough, Apple
     multichannel, renderer, content display match, start portrait, both
     completion thresholds, skip enabled and provider, `_netPatience`,
     `_netBuffer`, and `_iptvDecoderMode` (declared among the flags at
     193);
   - **subtitle and language values (12):** only-foreign, forced-only,
     auto-sync, both default languages, size, style, colour, background,
     font index, bold, and `_allFonts`;
   - **built-in focus (56): 28 node/flag pairs in two owners of 28
     fields,** split by the rows that render them:
     - **video, audio and player-section rows (14 pairs):** aspect,
       content display match, IPTV decoder, renderer, tvOS software
       decode, default audio language, system audio effects, passthrough,
       Apple multichannel, tvOS stereo, tvOS legacy audio, start portrait,
       and the **network pairs** `_netPatienceFocusNode`/`_netPatienceFocused`
       and `_netBufferFocusNode`/`_netBufferFocused` (rendered by
       `_playerSettings`, 2496 and 2506);
     - **subtitle, completion and skip rows (14 pairs):** default subtitle
       language, only-foreign, forced-only, auto-sync, size, style, colour,
       background, font, bold, both completion thresholds, skip enabled and
       skip provider.
5. **Callback identity.** At all 35 sites the checker compares the receiver
   path and the member. One of those sites is `_openPlayerSettings`, which
   must reach the layout as the State's own tear-off.

   The negatives are a wrapping closure and a same-class receiver swap. The
   36 listener closures are anonymous and never removed, so they have no
   identity contract.
6. **Test accessor.** As in PikPak, this is a `@visibleForTesting`
   top-level function that returns `Map<String, Object?>`. It exposes fresh
   value snapshots and the **real setter and action tear-offs**. Its key set
   is frozen at step 0.

   Once the owners move, its body moves into the bridge as one function
   over the composition. The facade keeps only a forwarder of at most 5
   lines.
7. **No new `const`; destination-lint baseline.** The original file under
   the root configuration has **12** diagnostics, all
   `deprecated_member_use`. The destination
   `lib/features/analysis_options.yaml` adds `directives_ordering` and
   `prefer_const_constructors`, so the same code there yields **29**: the
   12, plus 11 `directives_ordering`, plus 6 `prefer_const_constructors`
   on `SettingsInfoBanner(` (3267, 3454, 3638, 3822, 4105, 4204). CI's
   ignoring of infos is not the comparison. Follow the Debrid strict-lint
   procedure (`debrid-downloads-plan.md` Progress, "Conservative analyzer
   decision"; restated in `iptv-settings-plan.md` technique 5):
   - step 0 analyzes the **original** code under the unchanged destination
     lint configuration, in the original-code worktree, with import-URI
     qualification as the only edit, and records that original strict
     baseline;
   - the relocation comparison combines the root and strict observed
     baselines **by maximum observed count per identity, never by
     summing**;
   - a per-symbol check maps every destination diagnostic to the same
     original symbol, rule and message, with zero additions;
   - any new scaffold diagnostic is a failure, including
     `use_key_in_widget_constructors`, `prefer_const_constructors` on new
     code, and `directives_ordering` in a new file. No suppression, broad
     info ignore, or allowlist growth.

   The only allowed edits to moved code are import sorting and receiver
   qualification; no `const` is added.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, original strict-lint evidence, format-only commit, dependency report, manifest and config, configuration-scoped partition checker extension, accessor, characterization and baselines, source-text inventory, CI list, Linux capture script | Nothing moves. |
| 1 | Guard registration; the three generic row builders | Contract 11 |
| 2 | State owners by group; lifecycle verbatim | Contract 2 |
| 3 | `_loadSettings`, the mode setter, the macOS, iOS, Linux and Windows actions | Contracts 3–6 and 8. **Full-suite gate 1.** |
| 4 | DeoVR, built-in and subtitle setters; fonts; labels and getters | Contracts 7–9 |
| 5 | Tile builders, mode option, `_defaultsCard`, appearance, the five section builders, the partition | Contracts 10–14 |
| 6 | `build` into a layout section that receives `_openPlayerSettings`; the forwarder | Contract 1. Linux originals are a blocking prerequisite. |
| 7 | Final State, accessor forwarder, facade cap, `TEMP(playback_settings)` rejection, CI. **Full-suite gate 2.** | |

### Step 0

1. **Baseline.** Run `suite_evidence.py run playback_settings/base` and the
   whole analyzer on the unformatted HEAD, with tree provenance, on Flutter
   3.44.8. Each worktree gets its own parser-kernel cache, because PikPak's
   concurrent runs collided on a shared one. `suite_evidence.py check`
   already writes a per-run temp file (`4f3ee3b3`), so parallel worktrees
   no longer overwrite a shared `/tmp/suite_evidence_check.jsonl`; no
   tooling change is needed. Always invoke the executing worktree's own
   `dev/tool/suite_evidence.py`: `check` strips that script's checkout
   root (it has no `.env.json`), while `run` records its root and
   `compare` strips each run's recorded root. A run made from another
   checkout must not be compared by path.

   Also record the **original strict-lint baseline** (Technique 7) from the
   same revision, in the original-code worktree.
2. **Format-only commit.** Apply Technique 1 and commit it as
   `style(playback-settings): step 0 format original`. The same commit
   adds the facade to the format and analyze lists in `checks.yml`. The
   facade has 0 warnings, so the analyzer allowlist gains no entries.
3. **Dependency report** (`docs/refactoring/playback-settings-deps.md`). It
   covers:
   - every leaf, with the per-entry wiring checklist;
   - which builders use the State's `context` (`_defaultsCard` and every
     section) and which take it as a parameter;
   - the owner sets and handles;
   - the facade simulation and cap;
   - each static's owner.
4. **Checker.** Write the manifest and config, with fixtures based on the
   real config. Negatives:
   - a wrapping closure;
   - a receiver swap;
   - a reordered listener;
   - swapped first-two and last-two disposals;
   - a lifecycle statement moved out;
   - a partition element reordered or split;
   - a platform piece out of order;
   - the self-push moved into the feature.

   Add the configuration-scoped partition extension (Technique 3) with its
   positive real-join fixture and its reorder, omission, duplication and
   split-element negatives. Every existing checker config and self-test
   runs unchanged and passes before the extension is committed.

   Use LF line endings and run the staged diff check before every commit
   (PikPak's TSV writer emitted CRLF).
5. **Harness.** It uses:
   - the root `flutter_test_config.dart` (legacy `ProfileRuntime`);
   - `SharedPreferences.setMockInitialValues`;
   - `PlatformUtil.debugSetTvOS` and `debugSetAndroidTvCached`;
   - a fake `FilePicker.platform`;
   - a temp-dir `PathProviderPlatform`;
   - a `debrify/tvurl` mock handler and a fake `UrlLauncherPlatform`;
   - `tester.runAsync` for real host detection;
   - a reset of the subtitle settings service;
   - **font isolation without touching the services.**
     `SubtitleFontService.resetProfileScope()` clears only `_profilePrefs`;
     the singleton keeps `_devicePrefs`, `_cachedCustomFonts` and
     `_loadedFontFamilies`, and `AppStorage` caches its directories. So:
     reset or override `AppStorage` explicitly in every test
     (`debugReset`, or `debugOverride` to the temp dir); keep one stable
     device-prefs fixture for the whole file; and return the custom-font
     list to its starting state through the existing public
     `importCustomFont`/`removeCustomFont` operations. Where that can't
     isolate a case, run it in a separate test file (its own isolate).
     Before freezing, prove the import/remove fixtures pass when run in
     different orders. The font and subtitle services stay unmodified;
   - a committed two-profile registry for scope tests (the
     `connection_secret_editor_repair_test.dart` recipe).

   Schedule a frame explicitly after post-frame focus callbacks. Prove that
   one fixture passes on the original first.
6. **Characterization tests,** recorded against the formatted original in
   a detached worktree. Rules:
   - drive the real entry points;
   - re-read state after acting;
   - assert exact key/value maps;
   - prove each assertion on the original before freezing it;
   - add mutation proofs, on the original only and never committed.

   | Contract | Coverage |
   | --- | --- |
   | 1 Routing | Each section renders its own builder, header and title. Also: the spinner; the banner text for `external` and `deovr`, with "Choose player"; the unsupported branch, by source guard. The 6 existing navigation tests are kept. |
   | 2 Lifecycle | Source guards on the `initState` order (all 36 listeners) and the 42-disposal sequence; unmount during a pending load; a focus change flips its ring flag. Mutations that must fail: a swapped disposal pair; a reordered listener. |
   | 3 Load | Seeded prefs give every published value (read through the accessor) for each section. An unknown patience or buffer falls back to `standard`; an unavailable skip provider falls back to `auto`. A storage throw clears the spinner and shows "Failed to load settings". TV entry focus with `debugSetAndroidTvCached(true)` seeds the first stop, but not when a concrete node already has focus. |
   | 4 Writes on open | A write-recording preferences fixture captures the **ordered** writes of one open, from an empty and from a seeded profile. **Renderer:** absent mode → `android_video_renderer_mode` = `'direct_mediacodec'`, then `android_video_renderer_gpu_migration_v1` = `true`; legacy `'direct_surface'` → the same two writes; a retained explicit mode (`'automatic'`) without the flag → only the flag; any open after the flag is set → no renderer write. Run on every host and for each section, because the call is unconditional. **Subtitle:** elevation 0 with no flag → the index becomes `SubtitleElevation.defaultIndex` and the flag is set; an explicit index → only the flag; a second open writes nothing. The renderer writes precede the subtitle writes. |
   | 5 Detection | tvOS (`debugSetTvOS`): the exact `canOpen` calls in `iOSExternalPlayer.values` order (the tvOS catalog, custom skipped), made only on Player; on a macOS host the simulated-tvOS run also performs the real macOS detection first, because desktop detection stays true alongside tvOS. macOS and Linux run real `which`: host-tolerant tile assertions, plus source guards on sites, arguments and order. iOS-mobile, Windows and Android `isTelevision`: source guards, with device verification **pending**. |
   | 6 Actions | macOS host: select (exact key and value); browse with the fake picker (exact arguments, three writes in order; cancel writes nothing); custom command (invalid → error and no write; valid → write); clear (keys removed, preferred reset, controller cleared, no dialog). tvOS select and scheme likewise; Linux in Docker; Windows by source guard. Snackbar texts. |
   | 7 Setters | **Every** setter, through the accessor's real tear-offs: exact keys, exact values, in order, and `setState` before the first write (observed while the write is held). The renderer setter's expected map includes both `android_video_renderer_mode` and `android_video_renderer_gpu_migration_v1` = `true`, in that order. The aspect setter's `player_default_aspect_index` path is asserted on desktop; its `player_default_aspect_index_tv` branch is unreachable there (`_isAndroidTv` is false and the tear-off cannot supply it), so it is a source guard with device verification **pending**. Host-reachable rows are also driven through the UI. |
   | 8 Scope | With two committed profiles, a setter writes only the active profile's key, and an imported font list is visible from both. **Route handoff, original-proved:** with a pushed playback page (via `pushSettingsPage`) over the gate, a profile switch through the picker entry pops the page by identity (it is disposed, not remounted). **Idle route** (loads and actions settled first): the incoming profile's open writes and reads only its own keys, and the outgoing profile receives no write after the pop. **Held boundaries**, characterized separately against the original: a write held before and after `ProfilePreferences` acquisition, and a pending font-picker result resuming after the switch, each recording where the write lands or the error it raises. |
   | 9 Fonts | Import: a wrong extension is rejected with no copy; no extension is accepted; the null-path message; success puts the file in the temp `subtitle_fonts`, refreshes the list and shows the message. Remove: no dialog; the file is deleted; removing the selected font resets the selection; the message. |
   | 10 Navigation | Each host-reachable appearance tile pushes its page: `PlayerDockPage` on desktop, hidden under `debugSetTvOS(true)` (`!PlatformUtil.isTelevision`); `PlayerGuideStylePage`; `PlayLoaderStylePage`; `SubtitlePriorityPage`. The `_isAndroidTv` destinations — `TvPlayerControlsStylePage` and the `DebrifyTvPlayerStylePage` tile — are unreachable on desktop: source guards on their predicates and targets, with device verification **pending**. No new seam is added to reach them. "Choose player" pushes Player and reloads on return (existing test 5). A source guard keeps the self-push in the facade. |
   | 11 D-pad | Arrow keys through dropdown and checkbox rows, not wrapping at either end. Mode rows are single stops. The macOS `TvTextField` arrows. Existing test 6. Night-mode activation: accessor, source guard, and a pending device check. |
   | 12 Callbacks | Checker identity at all 35 sites, plus a widget test that the "Choose player" `onTap` is the State's `_openPlayerSettings`. |
   | 13 Platform | Source guards: each member's predicate multiset is unchanged, and E1–E15 stay in order. |
   | 14 Helpers | Byte hashes of both helper files at every step; the preview style is compared with `buildTextStyle`. |

   **Goldens,** on macOS and on Linux (from Claude's Docker capture):
   - Player in `debrify` mode;
   - Video;
   - Audio;
   - Subtitles, with the preview;
   - Video with the managed-externally banner.

   External-mode Player is excluded because it depends on host detection.

   Record `base2` after the accessor and `base3` after the tests. Each
   comparison may show only added, passing identities. Analyze the new tests
   before `base3`: Debrid's first baseline gained 37 brace diagnostics.
7. **CI list.** Add the new tests as concrete paths, plus
   `test/playback_settings_navigation_test.dart`, which is missing today.
8. **Source-text inventory.**
   - **Shape.** 20 bare radii and 4 token calls, unchanged by formatting;
     no radius has a trailing comma.
     - Per owner: mode option 3, dropdown 1, checkbox 2, setting dropdown
       1, night mode 3, preview 1, E3 2, E6 2, E9 2, E12 1, E13 2.
     - `kShapeResidue` totals exactly the 488 floor, so there is **zero
       slack**. The tile-builder destination goes in `kShapeResidue` and
       the others in `kExtractedShapeResidue`; the facade leaves
       `kShapeResidue` once its token calls move.
     - Assert exact per-file counts after every format run. The regex
       misses a radius that the formatter splits with a trailing comma.
   - **Theme registry.** Add exact per-directory patterns for
     `presentation/` and `presentation/legacy_playback_settings/` to
     `theme_surface_manifest.txt:6`.
   - **Guards to extend, keeping their purpose.**
     - `test/settings_tv_input_source_guard_test.dart` gains the facade and
       the feature; today it doesn't cover this page.
     - The `print(` redaction scan, `profile_source_guard_test.dart::profile,
       download, deep-link, and remote logs stay redacted` (326), already
       covers `lib/screens/settings` and gains the feature. It keeps its
       observed baseline outcome. The file's one observed pre-existing
       failure is a **different** identity,
       `profile_source_guard_test.dart::direct SharedPreferences opens stay
       inside reviewed adapters/stores` (7); it stays as observed and is
       not touched.
   - **Also update** `file_size_baseline.txt:14`, the architecture rules,
     and `checks.yml`, including any `test/support/playback_settings_*`
     helper.
   - **No change needed:**
     - `analyzer_allowlist.txt`;
     - `text_white_sweep.py`, which scans this path (it contains no
       "player") and finds 0 `Colors.white`;
     - `light_ink_inventory.py`, which is optional.
   - **Storage reference checks** run after step 3.
   - **Merging.** The IPTV-settings worktree edits several of these files,
     so keep every edit additive.
9. **Linux capture script**
   (`dev/tool/capture_playback_settings_linux_goldens.sh`). It resolves the
   checkpoint by its exact subject, `test(playback-settings): step 0
   original-code characterization checkpoint`, and uses the checkpoint's
   own tests and fixtures. Claude runs it in the calibrated image and
   commits the PNGs and provenance separately, before step 6. The Linux
   test stays non-strict through step 5.

### Per step and gates

As in the PikPak plan, with these specifics:
- **Analyzer comparison:** run with `--relocate
  lib/screens/settings/external_player_settings_page.dart=lib/features/playback_settings/`
  against the root and original strict baselines combined by maximum, plus
  the per-symbol strict check (Technique 7).
- **Suite evidence:** run `check`/`compare` with the executing worktree's
  own script (Step 0.1); the per-run temp file is already in place.
- **Manifests:** every manifest runs with its self-tests: settings, IPTV,
  TorBox, Real-Debrid, PikPak, IPTV-settings once integrated, and this one.
- **Focused tests:** run against the latest base.
- **Shape and helpers:** the per-file shape counts and the helper hashes.
- **Local CI:** the CI-equivalent commands and the staged diff check.
- **Gates:** run from committed source, with the evidence committed
  separately under a `gate` subject.
- **Wiring:** review each composition's wiring before pinning scaffolds.
  `mounted` and `context` stay live at their original sites, and nothing
  is hoisted.

## Definition of done

1. **Facade.** It is at most 400 formatted lines, or the measured step 0 cap
   with its documented exception. It holds the widget, the owner handles,
   the verbatim lifecycle, `_openPlayerSettings`, the forwarders and the
   wiring. Every caller compiles unchanged.
2. **Guard.** It registers:
   - the feature and its bridge;
   - the facade cap and the `TEMP(playback_settings)` rejection;
   - the back-import and cross-feature bans;
   - the 500-line caps;
   - the extended TV text-field and redaction guards.
3. **Manifests and characterization.** All manifest runs pass with their
   self-tests, and every characterization test passes unchanged. The macOS
   goldens are strict; the Linux originals are verified and strict.
4. **Analyzer.** There are no new diagnostics or suppressions against the
   max-combined root and original strict baselines; the per-symbol strict
   check has zero additions; and the allowlist check passes.
5. **Gates.** Gate 2 passes against the latest base and gate 1. The shape
   counts stay at 20 radii and 4 token calls, with the floor at 488.
6. **CI.** The local CI-equivalent checks pass, and remote CI is pending
   until Claude pushes. The CI list includes the new tests and
   `playback_settings_navigation_test.dart`. The failure allowlist gains no
   entries.
7. **Progress records** cover:
   - the commits and ownership;
   - the exceptions, with their exit milestones;
   - the seams: the format commit, the accessor, and the size raises.
8. **Pending device verification** is recorded for:
   - **Android and Android TV:** DeoVR, night mode and its activation key,
     the TV aspect key write, the `TvPlayerControlsStylePage` destination
     and `DebrifyTvPlayerStylePage` tile, passthrough, the renderer, the
     IPTV decoder, and `isTelevision`;
   - **iOS-mobile:** detection and the scheme;
   - **Windows;**
   - **real tvOS and desktop detection.**
9. **Stop after gate 2** and report.

## Explicitly not in scope

- `playback_settings_page.dart`, `playback_settings_section.dart`, the
  sibling style pages, and the other `lib/screens/settings/` pages.
- `ExternalPlayerService`, the player models, the storage classes, the
  subtitle settings and font services, `NetworkTuning`,
  `AndroidNativeDownloader`, and the settings search index with its label
  copies.
- Merging the near-duplicate platform cards, tile builders or `Shortcuts`
  copies.
- Bug fixes and behaviour changes, including the items below.

## Progress

### Step 0 — baseline and format checkpoint

- Dedicated `refactor/playback-settings` worktree starts at `452d8a8b`; Flutter
  3.44.8 / Dart 3.12.2. `flutter pub get` completed without lockfile changes.
  Untouched full suite `playback_settings/base`: 10,577 success, 13 failure,
  28 error, 20 skipped; stable committed tree
  `6ef59f2099e8a01e0bb0027dc4efec29733ce930`, no overlay or untracked input.
  These observed identities, not the historical allowlist, are authoritative.
- Original strict-lint evidence reproduces exactly 29 diagnostics (12
  deprecations, 11 import-order infos, six const-constructor infos). The root
  analyzer and per-symbol strict inventory are retained in the shared evidence
  namespace. Parser package/cache is isolated under `playback_settings/parser`,
  initialized with the pinned lockfile; every manifest run passes its package
  config explicitly.
- Workspace restriction decision: all original-code proofs run in this dedicated
  worktree before any extraction, with exact original hashes and tested-tree
  evidence. No other checkout/worktree is opened or modified. The strict-only
  original copy is under this worktree's ignored `build/` directory, using the
  unchanged destination lint file and import URI qualification only.
- Format proof: AST structure equal; token diff contains exactly nine inserted
  and one removed formatter-owned commas (positions in `format-token-proof.json`);
  unchanged comment multiset and 20 bare radii/four shape calls. All six original
  navigation identities pass against `base`. Whole analyzer comparison is PASS
  with zero additions/removals; the temporary strict/tool Dart copies were renamed
  to `.dart.txt` before the clean whole-repo check, since the analyzer scans
  ignored build directories too. Architecture, file-size and staged diff checks
  pass. The facade is added to both CI format/analyzer command lists.
- Temporary oversized facade: all original lifecycle, load/actions, values,
  focus resources and builders remain until steps 1–7. Format-only ratchet raise
  4,289 → 4,314 is intentional; extraction lowers it thereafter. Lifecycle stays
  whole; eventual facade cap is determined by the step-0 simulation.
- The obsolete cloud `**` finding is removed: `452d8a8b` already registers
  explicit per-directory patterns. New playback theme entries will use the same
  explicit pattern convention. No push, branch switch, dependency upgrade,
  behavior fix, assertion weakening or allowlist growth is authorized.


### Step 0 — original characterization preparation

- Frozen all 214 original leaves and the 133-field owner membership in the
  dependency report; normal facade simulation is 351 lines, so the final cap
  remains 400. Accessor seam has 191 keys, fresh collection snapshots and real
  action/setter tear-offs. Accessor-only full `base2` compares exactly with
  `base`, and its whole analyzer adds/removes no identities.
- Original characterization covers 123 new identities across values, views,
  actions, interactions, committed-profile boundaries, acquisition timing and
  source guards. The original-focused draft is 145 successes and the one
  observed pre-existing profile storage-adapter guard failure; comparison with
  `base` passes with only added passing identities. Final staged proof and
  `base3` are recorded before extraction. Five macOS original PNGs were captured
  before extraction; only original capture uses golden update flags.
- Three original-code mutations fail their exact tests: swapped first disposals,
  reordered listeners, and negated subtitle-bold publication. The original
  source is restored byte-for-byte. Font import/remove cases also pass with
  random ordering seed 731. No proved assertion was weakened.
- Conservative fixture decisions: real host detection runs in `tester.runAsync`;
  one stable device-preferences object lives per isolate; dropped `loadFonts`
  work drains before resetting caches; font cleanup uses existing public APIs.
  Preference acquisition replacement has a separate isolate. The gate fixture
  uses existing deterministic test typography and invokes picker actions in the
  real async zone. Down at the macOS command field's lower boundary stays there;
  Up exits. Incoming/outgoing aspect values are explicitly seeded separately.
- The original profile hazards are now reproduced: before acquisition a setter
  captures B; an already-issued renderer write lands in A and the next write
  rejects its stale session; a pending font picker imports device-wide and selects
  in B after its route pop. Idle picker handoff pops the pushed route by identity,
  disposes the State, preserves A, and opens a new State reading/writing B.
- The URL-launcher test interface is promoted from the already-locked transitive
  2.3.2 version to an exact dev dependency; no version or runtime dependency
  changes. Concurrent Flutter commands initially collided in ephemeral pub-get
  cleanup; subsequent checks use `--no-pub` after this worktree's completed get.
- The retained-preamble checker extension is opt-in, with a real original join
  positive and complete partition/callback negatives. Every named callback
  rejects closures, same-class receiver swaps, wrong members and missing named
  arguments. The original 36-listener and 42-resource sequences, predicates,
  detection/read order, unsupported branch, TV aspect key, navigation and helper
  hashes remain pinned. TV input/redaction guards and explicit per-directory
  theme registry entries are extended additively. Linux capture script resolves
  this checkpoint by its exact subject and passes shell syntax checks.


### Step 0 — frozen original evidence

- Full `playback_settings/base3`: **10,700 successes / 13 failures / 28 errors /
  20 skips**, PASS against `base2`. The unfiltered identity audit verifies all
  prior outcomes exactly and exactly 123 added successes; staged tested tree
  `a7d92d14d0fa50b9b8b8fa3a9c3a03d9c69b203e`, no untracked inputs or tree changes.
  `original-freeze` separately proves every characterization identity on the
  unchanged formatted original/accessor. The source guard pins the unsupported
  branch body independently of the named root-build annotation exception.
- Root analyzer is unchanged (1,635 records). Original root/strict evidence is
  combined by maximum: 1,652 records. Per-symbol proof: 12 current / 29 original
  strict, zero additions and zero scaffold diagnostics. CI format: 1,473 files,
  zero changes. Scoped CI analyze and the unchanged five-warning allowlist pass.
  All six manifests/self-tests pass with the isolated parser, including all
  214 playback leaves, every named callback and the real partition fixtures.
  Architecture, sizes, storage keys/references and staged diff pass.
- Exact retained-State callback aliases permit the legal public record field
  `openPlayerSettings` while preserving `_openPlayerSettings` as the State's
  actual tear-off. Direct positive, closure and receiver negatives prove this
  configuration-scoped spelling; other configs retain their behavior. Fresh CI
  clones initialize the source guard's own pinned, isolated parser package.
- CI selector decision: the pre-existing known-failure inventory names the
  WebDAV hot-merge suite but its concrete test list omitted that file. Add its
  existing path (no code/assertion/failure-list change) so the CI command can
  exercise both already-observed listed failures. The full baseline already
  contains those exact identities. Full-suite historical helper discrepancies
  remain historical evidence, never accepted with a record/update flag.
- Actual CI behavior command passes: 3,157 successes and the two unchanged
  listed failures. The concrete selector repair is additive. Context-guard
  checks are enabled for every receiver-qualified manifest row, and the final
  real-config/self-test replay passes. Historical full-suite helper replay
  still reports original discrepancies; no failure inventory is changed.

### Step 1 — parameter-only row builders

- Move the three generic row builders into public presentation functions. Their
  original dependency report is parameter-only; real production callers use
  the new functions and the three separate Shortcuts/Actions bodies remain exact.
  No owner/composition scaffold is introduced in this step.
- Register the feature, exact legacy bridge prefix, 500-line file limits,
  service/import boundaries and bidirectional settings/IPTV-settings bans.
  Final facade cap/TEMP rejection remains scheduled for step 7.
- All six manifests plus self-tests pass, including 214 playback leaves and
  all 35 callback identities/negative fixtures. Focused `step1` compares PASS
  against `base3`: 145 successes and the same original profile source failure.
  Strict-symbol proof: zero additions/scaffold diagnostics; max-combined whole
  analyzer comparison PASS. CI format, scoped analyzer/unchanged allowlist,
  behavior selector, architecture, sizes, storage and staged diff pass.
- Facade ratchet is lowered to 4,231 lines. Exact shape ownership moves four
  radii into the three functions: total remains 20 radii/four token calls and
  floor 488. Original characterization/fixture/helper/macOS PNG hashes match.
  Linux artifacts supplied during this step remain outside this source commit.

### Linux original artifacts — separate checkpoint

- Verify all five supplied SHA-256 hashes, source revision
  `7bf567c9cc2d728d1a5ef3a0769c6b965628eb4b` and both five-test passing
  capture/strict logs. Commit PNGs separately with adjacent provenance.
- Capture used calibrated `debrify-flutter:3.44.8`, linux/amd64 Ubuntu 24.04,
  official SDK and sqlite development library; 14 cloud Linux originals were
  strict-reverified after the sqlite layer. Remote Actions were unavailable
  because of the spending limit. Full provenance/logs remain in the evidence
  namespace. Linux default stays non-strict through step 5 as planned, then
  becomes strict before moving the layout. macOS cannot validate Linux pixels.

### Step 2 — frozen field owners and whole State lifecycle

- Step 1 source checkpoint: `acd2f2ba`; separate Linux artifact checkpoint:
  `a69da7c8`. Move all 133 fields into the ten frozen owners (largest: 28).
  Initializers stay at declarations; all 12 implicit-null fields retain no
  initializer. Actual State handles bind one owner each, with no constructor
  actions; all reads, writes and accessor snapshots use those same owners.
  Review every field entry against the dependency report before pinning handles.
- Keep initState/dispose whole in State, including original analytics, the
  initial load, all 36 listener closures and the 42 ordered disposals followed
  by super. Exact comment multiset proof: 196 original/current comments.
  Trailing field comments move with their own fields, including orphan groups.
- Conservative checker decision: the frozen accessor needs an opt-in borrowed
  receiver rule after fields move. Normalize only its exact registered paths
  and frozen members; wrong-owner/same-class receiver negatives run directly,
  independently of scaffold failures. Other configurations have no such rule.
- `step2` focused comparison against latest `base3`: 145 successes and the same
  observed original profile guard failure; no identity changes. Whole analyzer
  comparison PASS; strict per-symbol proof has zero additions and zero scaffold
  diagnostics (12 current vs 29 original strict). Local CI checks pass with the
  unchanged allowlists; all six manifests/self-tests pass. Root analyzer exit 1
  remains original vendor errors, with unchanged identities, not a new failure.
- Facade ratchet: 4,120 lines. Exact shape counts remain 20 radii/four token calls
  and floor 488; original characterization/fixture/helper/macOS hashes match.
  No new const, lifetime owner, storage operation or listener is introduced.

### Step 3 — load and external actions; gate deferred for review closure

- Step 2 source: `a58f052f`. Move load, mode and four platform action groups
  verbatim. Review every step-3 dependency-report entry and actual record binding
  before pinning: same field owners, parameter types, real State setState,
  live mounted/context/section and direct action members; constructors only
  retain dependencies. The original loadFonts tear-off remains borrowed from
  State until step 4. Initial load still enters synchronously in initState.
- All six manifests/self-tests pass; focused `step3` compares PASS to `base3`
  (145 successes and the same original guard failure). Whole/max analyzer and
  strict symbol comparisons pass with zero additions/scaffold diagnostics.
  CI format, scoped analyzer/unchanged allowlist, behavior selector, architecture,
  sizes, storage keys/references and staged diff pass. Shape/helper/test hashes
  remain exact. Facade ratchet is 3,489 lines.
- Independent step-0 review arrived after source verification. Commit this
  verified source checkpoint, close all findings in a separate original-proved
  step 0b, adopt its new base, then run gate 1. No gate is claimed yet.

### Step 0b — independent review closure (after source step 3)

- Verified source step 3: `ded9f666`. Cherry-pick shared interpolation resolver
  `def4e304` as `5a380c77`, retaining Codex/Claude attribution. All 35 playback
  callback sites and their negatives remain unchanged.
- User explicitly authorized a detached original proof worktree at `7bf567c9`.
  Create it only under this worktree's ignored `build/step0b-original`, prove all
  changed/new cases there, and remove it before the next whole-root analyzer.
  No main checkout or pre-existing other worktree is used. App source is unchanged
  except temporary scratch/mutation proofs, restored byte-for-byte each time.
- P1 conservative structural decision: the join retains only locals actually
  used by E1/the join. Neither theme nor t is used there; both remain verbatim
  only in their platform pieces. The opt-in checker reconstructs their identical
  original locals for whole-method comparison. Positive/negative fixtures cover
  the real empty-preamble join and a genuinely split E3 child list across iOS/
  Linux pieces. Scratch real join compiles all six navigation cases; unchanged
  destination strict lint gives exactly 29 original diagnostics, zero new
  diagnostics and zero warnings. No new const or allowlist entry is added.
- Strengthen concrete TV focus retention using the later content-match row,
  rendered with simulated tvOS. Exact dropdown traversal pins first → middle →
  last and both ends; checkbox end targets stay exact. Mode Down targets the
  External Player row. Non-macOS command-field cases explicitly skip.
- Seed all omitted VR, tvOS, passthrough, Apple and external-player keys away from
  defaults. Simulated tvOS makes its three values/Apple and iOS scheme reachable;
  native desktop still loads its own external keys. Android-only VR/passthrough
  seeds intentionally remain unread on desktop, with original guards/order pinned
  and device execution pending. No fake Android seam is introduced.
- Profile assertions pin A's initial ordered migration writes, zero A writes
  during the picker handoff before clearing, and B's exact three ordered page
  migration writes after its original defaults bootstrap. Removing B's renderer
  migration fails, so the incoming assertion cannot pass vacuously.
- Second-open cases now mount a fresh State. Font import pins the complete ordered
  device-list/selection writes; invalid command/scheme errors use exact original
  text. The storage failure resets preference acquisition in the views isolate
  and uses failRead; its exact original snackbar is asserted. Golden test bodies,
  all ten PNGs and the player helper files stay unchanged.
- Source predicates are ordered, including E1–E15; detection sites, arguments,
  enclosing read/guard prefix and all five detector calls are pinned from the
  original. Source tests own a checkout-local pinned parser/kernel and never
  initialize or recompile the shared evidence parser.
- Eight original-only mutations fail their intended assertions: focus guard,
  Apple/tvOS/external-command load, dropdown Down target, incoming migrations,
  platform-element order and detector arguments. Original focused freeze has
  130 successes (all 124 characterization identities plus six navigation cases).
  New test analyzer has zero diagnostics. Mutation logs/proofs and all accepted
  test hashes are in `playback_settings/`; no assertion is weakened.
- Latest original `base4`: 10,701 successes / 13 failures / 28 errors / 20 skips;
  comparison to `base3` PASS with exactly one added success and every old outcome
  unchanged. Stable tested tree `618aa214e5955f4f1cb584891a7f7ebb0c3cb563` at
  `7bf567c9`, staged review-only test/tool overlay, no untracked inputs. Current
  replay: 146 successes and the same original profile guard failure, PASS versus
  `base4`. All six manifests and local CI-equivalent checks pass with unchanged
  inventories. Gate 1 will compare committed current source against `base4`.
- Record the previously omitted accessor size raise: original formatted facade
  4,314 → 4,515 with the 191-key test seam; this temporary raise exits when its
  body moves in step 7. The 351-line sizing artifact and AST span breakdown are
  now preserved in evidence and documented in the dependency report. The sketch
  excludes final import details; step 7 measures the compiling facade again.
- CI selector decision: retain the existing WebDAV hot-merge test path solely
  because the unchanged exact CI failure inventory requires its observed failure
  to be exercised. Dropping it fails the missing-known-identity check; filtering
  or editing the inventory would weaken that check. No WebDAV code, assertion or
  failure entry changes; the original whole baseline already observes it.

### Gate 1 — committed source after step 0b

- Source `0a9ec24736b43c6244d15901dd52cba48efe7be2`, tested tree
  `34abc7614d8cb4318111b396b786553a4e24e11e`: unfiltered full suite
  10,701 success / 13 failure / 28 error / 20 skipped. Every outcome identity
  equals the latest original `base4`; comparison PASS, zero additions/removals
  or changed outcomes. Same SDK, stable committed tree, no overlay/untracked
  inputs. `gate1.env.json`, `gate1-complete-identity-audit.json` and comparison logs
  preserve the evidence in `playback_settings/`.
- Historical helper replay still reports its original stale failure inventory;
  the exact observed original comparison is authoritative. No failure inventory,
  assertion or analyzer allowlist changes. This commit records evidence only.

### Step 4 — instant setters, fonts and labels

- Moved all 44 step-4 manifest entries: 33 instant setters, font operations,
  three unchanged statics and live label/index getters. Wiring reviewed before
  scaffold pinning (`step4-wiring-review.json`): the same owner instances and
  State `setState` tear-off; live `mounted`/`context`; getter bodies read current
  values. No constructor actions, preference/service changes or new consts.
- Facade 3,125 lines; extracted files at most 309 lines, composition 187.
  All six manifest/self-test runs pass. Focused replay: 146 successes and the
  same original profile-adapter guard failure; PASS against `base4`. Whole
  analyzer relocation/max comparison and per-symbol strict comparison PASS,
  zero additions/scaffold diagnostics. Local CI passes with unchanged inventories.
- Formatter decision: one retained radius wraps with a trailing comma after
  receiver qualification. Normalize only such playback literal calls in the
  shape source counter; preserve all other feature inventories. Initial broad
  normalization exposed unrelated historical omissions and was discarded.
  Final scoped check retains all 20 original radii/four token calls and floor 488;
  affected shape, focused, CI and whole-analyzer checks were rerun successfully.
  Frozen step-0b characterization, original PNGs and helper hashes are unchanged.

### Step 5 — builders and platform partition

- Moved all 13 step-5 entries and split the external list into the exact five
  configured whole-element ranges. E1 remains inline; join has no theme/t locals;
  each piece retains both original locals where used. Join borrows only core and
  the five real piece tear-offs. The step-0b real join scratch compile and strict
  analyzer proof already passed; production join adds zero diagnostics now.
- Per-entry/piece wiring reviewed before pinning (`step5-wiring-review.json`):
  live State context, lexical builder contexts, original owner instances, real
  setter/action tear-offs, live completion options getter. No new widget classes,
  consts, combined platform cards or navigation changes. Original comment-token
  multiset remains exactly 192. All 35 callback sites and negatives pass.
- Facade 660 lines; largest feature file 433 (subtitle section), composition
  372, external join 36. Six manifests/self-tests, local CI, focused `base4`
  comparison, whole analyzer/max comparison and strict symbol comparison PASS.
  Focused outcomes remain 146 successes plus the same original guard failure.
  Shape totals 20/four, floor 488; frozen characterization, PNG/helper hashes
  unchanged. Linux tests remain non-strict at this checkpoint as planned.

### Linux prerequisite — verified originals and strict tests

- Original artifacts remain separately committed at `a69da7c8`, from exact
  checkpoint `7bf567c9`. Reverified all five hashes and original capture/strict
  logs and calibrated Linux provenance; no PNG changes.
- Before moving `build`, Linux golden comparison is strict by default. Sole
  frozen-test delta is `requireLinux` false → true, byte-proved against step 0b;
  original strict capture already passed with the equivalent true define.
  No golden body/assertion changes or recapture. macOS views 27/27 pass,
  affected test analyzer zero diagnostics.
- Calibrated `debrify-flutter:3.44.8`, linux/amd64: current step-5 source plus
  the flag passes all five original PNG comparisons without update flags.
  Read-only archive of this dedicated worktree's staged tree was tested in
  the disposable container; host source/lock/goldens unchanged. Exact tree,
  image ID, hashes and logs are in `linux-strict-prerequisite.json` and related
  evidence. This separate commit closes the prerequisite before step 6.

## Found, not fixed

All of these are pre-existing, and the extraction keeps each one exactly.
- **Unguarded calls after an `await`.** 20 `setState` calls have no
  `mounted` check: 748, 763, 792, 815, 820, 848, 874, 880, 897, 924, 950,
  956, 973, 1000, 1026, 1032, 1049, 1076, 1104 and 1110. Four controller
  `.clear()` calls are also unguarded: 879, 955, 1031 and 1109.
- **No error handling** in the 33 instant-save setters or
  `_removeCustomFont`. Their Futures are dropped, so a failed write becomes
  an uncaught zone error after the UI has already changed.
- **No stale-result guard** on `_loadSettings`. The reload from
  `_openPlayerSettings` can race an earlier load.
- **No confirmation:** removing a font deletes a device-wide file, and
  clearing the custom app, command or scheme isn't confirmed either.
- **Raw errors:** snackbars show the raw `$e`.
- **No `didUpdateWidget`:** a reused State keeps a stale analytics name and
  detection scope.
- **Platform checks:**
  - two TV truths;
  - redundant `isPhone` (2340) and `Platform.isAndroid && _isAndroidTv`
    (2595) checks;
  - an unreachable unsupported branch.
- **DeoVR mode off Android:** a stored `deovr` mode on a non-Android device
  shows no DeoVR card, yet the other sections still say DeoVR manages them.
- **Writes on open on every host:** the unconditional renderer read
  migrates `android_video_renderer_mode` and sets its flag even on iOS,
  tvOS and desktops, which never use it.
- **Unguarded font index:** `_allFonts[_subtitleFontIndex]` (3172, 3177).
- **Mixed focus rings:** macOS uses a border plus a shadow, while iOS, Linux
  and Windows use a shadow only.
- **Legacy surface:** 20 legacy bare radii, hard-coded English, and label
  copies in the search index that no test checks.
- **Late writes after a profile pop.** Popping the page doesn't cancel
  in-flight work: an issued write can land after the switch, a later one can
  be rejected as stale, and a pending picker result can resume its storage
  calls in the new session.
