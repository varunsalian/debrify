# Local Android TV testing

From the repository root:

```sh
zsh tool/tv_test.sh
```

Reuses or starts the `debrify_tv` AVD, opens the installed app, and opens
http://127.0.0.1:18766/ for D-pad control. Keep the terminal open when it
starts the remote. View playback in the emulator window. Click the remote
page before using arrows, Enter, or Escape. Hold OK sends an Android long press.
The remote binds only to localhost. Screenshots depend on emulator support;
the current emulator may return an empty screenshot.

To rebuild and update the installed release without clearing its data:

```sh
flutter build apk --release --target-platform android-arm64
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-release.apk
```

Use `adb devices` if the emulator serial differs. Do not uninstall to resolve
a signing mismatch without first backing up app data. The release version
uses the repository's current version; this workflow does not publish a release.

Use real hardware for final codec, HDR, passthrough and performance checks.
