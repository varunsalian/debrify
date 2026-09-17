# Personal installation

The Personal build is an opt-in second installation whose operating-system
identity and private data container are separate from the normal Debrify app.
Existing `flutter run`, `flutter build`, Gradle, Xcode, and release commands keep
their original identifiers and behaviour.

Build from the repository root:

```sh
tool/build_personal.sh android Release
tool/build_personal.sh ios Release
tool/build_personal.sh tvos Release
tool/build_personal.sh macos Release
```

Use `Debug` as the optional second argument for a debug build. Apple builds use
the signing team already configured in the corresponding Xcode project.
Artifacts are written beneath `build/personal/` for Apple platforms; Android
uses Flutter's normal `build/app/outputs/` directory.

| Platform | Normal identity | Personal identity |
| --- | --- | --- |
| Android | `com.debrify.app` | `com.debrify.app.personal` |
| iOS | `com.varunsalian.debrify` | `com.varunsalian.debrify.personal` |
| tvOS | `com.varunsalian.debrifytv` | `com.varunsalian.debrifytv.personal` |
| macOS | `com.example.torrentSearchApp` | `com.example.torrentSearchApp.personal` |

The tvOS Personal build intentionally strips App Group entitlements. This keeps
it away from the normal installation's Top Shelf container; Top Shelf is not
expected to work in that build.

Deep-link schemes are unchanged, so when both copies are installed the OS may
choose either app for a shared scheme such as `debrify://` or `magnet:`.
