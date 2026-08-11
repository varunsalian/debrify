# Why there is no Package.swift here

`flutter-tvos` gives Swift Package Manager ownership of any plugin that ships
a `Package.swift`, and skips it in CocoaPods. That does not work for this
package.

Upstream `media_kit_video` **does not support SPM** — stock Flutter says so out
loud when building for iOS:

```
The following plugins do not support Swift Package Manager for ios:
  - media_kit_libs_ios_video
  - media_kit_video
```

Its Swift sources rely on the CocoaPods build environment: many files (e.g.
`common/UtilsProtocol.swift`) reference `NSObject` and `FlutterTexture` with no
`import` at all, which only compiles through the podspec's header/module setup.
Under SPM they fail with `cannot find type 'NSObject' in scope`.

The generated manifest is kept as `Package.swift.disabled` for reference.
Renaming it back will break the build unless every source file is given
explicit imports first.
