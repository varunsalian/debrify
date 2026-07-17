# Debrify for Apple TV

Native SwiftUI tvOS implementation of Debrify. The parity target and platform adaptations are defined in [GOAL.md](GOAL.md).

## Requirements

- Xcode with a tvOS SDK (tvOS 17 or newer)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate the project after changing `project.yml`
- An Apple Developer team for device installation

## Generate and build

```sh
cd tvos2
xcodegen generate
xcodebuild \
  -project DebrifyTV2.xcodeproj \
  -scheme DebrifyTV \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath /tmp/debrify-tv-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The project intentionally does not commit a development-team identifier. Open `DebrifyTV2.xcodeproj`, select your team and an Apple TV, and Run to install on a physical device. Change the generic bundle identifier in `project.yml` when needed for signing.

## Tests

Install a tvOS Simulator runtime through Xcode Settings > Platforms, then run:

```sh
xcodebuild \
  -project DebrifyTV2.xcodeproj \
  -scheme DebrifyTV \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  test
```

This checkout was validated with a generic tvOS Simulator build and a successful `build-for-testing`. Execution of the unit bundle requires an installed tvOS Simulator runtime.

## Credential setup

Provider API tokens, WebDAV passwords, Xtream passwords, optional Trakt client IDs, and optional TMDB read tokens are entered on Apple TV and stored in Keychain. No API key, client secret, provider token, or personal service URL is committed to this target. The app deliberately has no plaintext credential import or unauthenticated LAN setup-transfer feature.
