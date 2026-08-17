Pod::Spec.new do |s|
  s.name             = 'media_kit_libs_tvos_video'
  s.version          = '0.0.1'
  s.summary          = 'tvOS dependency package for package:media_kit'
  s.description      = 'Vends libmpv + ffmpeg xcframeworks with Apple TV slices.'
  s.homepage         = 'https://github.com/media-kit/media-kit'
  s.license          = { :type => 'MIT' }
  s.author           = { 'spike' => 'spike@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  s.vendored_frameworks = 'Frameworks/*.xcframework'

  s.platform      = :tvos, '17.0'

  # STATIC, deliberately. The Podfile uses `use_frameworks!`, which would make
  # this a DYNAMIC framework — and a dynamic framework has to resolve its own
  # symbols at build time. libmpv is a static archive force-loaded into the APP
  # executable, so a dynamic renderer framework cannot see mpv_render_context_*
  # and fails with undefined symbols. Static means these objects link into the
  # same executable the mpv symbols land in, where they resolve normally.
  s.static_framework = true
  s.swift_version = '5.0'

  # Deliberately NO `s.dependency 'Flutter'`. The Flutter CocoaPod does not
  # declare tvOS support, so depending on it fails `pod install` outright with
  # "platform of target Runner (tvOS) is not compatible with Flutter". The
  # framework is instead found via a search path the host app's Podfile
  # populates — same approach flutter-tvos's own generated plugins use.
  s.xcconfig = {
    'FRAMEWORK_SEARCH_PATHS' => '"${PODS_ROOT}/../Flutter"',
    'OTHER_SWIFT_FLAGS'      => '$(inherited) -DTARGET_OS_TV',
  }

  # These builds ship STATIC archives. Nothing in the app references an mpv
  # symbol at link time (dart:ffi resolves at runtime) and the link runs with
  # -dead_strip, so without -force_load the linker discards every object file
  # in libmpv.a and the runtime lookup then fails in a way that looks like a
  # loading bug.
  #
  # Path notes, both learned the hard way:
  #  * Applied to the USER target - that is what links the executable the
  #    symbols must land in.
  #  * ${PODS_TARGET_SRCROOT} is a POD-target variable and expands to EMPTY
  #    here, producing "/Frameworks/..." and a "build input file cannot be
  #    found" error. ${BUILT_PRODUCTS_DIR} is valid in the user target.
  #  * CocoaPods extracts the correct xcframework slice into
  #    XCFrameworkIntermediates, so this needs no per-SDK variants - the
  #    device/simulator choice has already been made by the time we link.
  s.user_target_xcconfig = {
    # CocoaPods auto-links the .framework-wrapped slices but gives the bare
    # .a slices only a -L search path, so libass/libplacebo/etc must be named
    # explicitly or the link dies on _ass_add_font and friends.
    # The .framework-wrapped ffmpeg slices are not propagated to the app
    # target either (the pod itself has no code linking them), so name
    # them too or the link dies on av_buffer_alloc / av_base64_encode.
    # -force_load was the obvious fix here and is WRONG: it pulls in every
    # object in libmpv.a including mpv's own CLI entry point, which collides
    # with the app's (duplicate symbol '_main', 7 of them). Naming the
    # client-API entry points as undefined with -u instead makes the linker
    # pull exactly the objects defining them plus everything those reference
    # transitively: the whole player, none of the CLI.
    #
    # CocoaPods auto-links neither set for the USER target - the bare .a
    # slices get only a -L search path and the .framework-wrapped ffmpeg ones
    # are not propagated - so both are named explicitly.
    #
    # Rebuilt set (TVOS_LIBMPV_UPGRADE_PLAN.md): every slice is now a bare .a
    # inside its xcframework, so everything is named with -l and nothing needs
    # -framework. Three deltas from the karelrooted v0.0.1-beta set:
    #  * TLS is openssl (-lcrypto -lssl), not gnutls: ffmpeg is configured
    #    --enable-openssl and its configure refuses both at once. So
    #    -lgnutls -lnettle -lhogweed -lgmp are gone.
    #  * -lglslang is gone: shaderc_combined already contains glslang and
    #    SPIRV-Tools, which is the point of the "combined" archive.
    #  * -lluajit51 is now -lluajit. The archive is shipped dot-free on
    #    purpose: Xcode's OTHER_LDFLAGS parser splits -lluajit-5.1 at the dot,
    #    so the linker sees "-lluajit-5" and fails to find it.
    'OTHER_LDFLAGS' => '$(inherited) -lmpv -lavcodec -lavdevice -lavfilter -lavformat -lavutil -lswresample -lswscale -lass -lbluray -lcrypto -ldav1d -lfreetype -lfribidi -lharfbuzz -llcms2 -lluajit -lMoltenVK -lplacebo -lpng -lshaderc_combined -lssl -luchardet -Wl,-u,_mpv_create -Wl,-u,_mpv_render_context_create',
  }
  # Apple frameworks libmpv's own sources reference. Its audiounit audio
  # output (audio_out_ao_audiounit.m) needs AVFoundation + AudioToolbox; the
  # GPU/decode paths need the rest. Without these the link fails on
  # _AVAudioSessionCategoryPlayback, _AudioUnitInitialize and friends.
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreAudio', 'CoreMedia',
                 'VideoToolbox', 'CoreVideo', 'CoreGraphics', 'CoreText',
                 'QuartzCore', 'Metal', 'MetalKit', 'OpenGLES', 'Security',
                 'UIKit'
  s.libraries = 'z', 'bz2', 'iconv', 'c++', 'resolv', 'xml2'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
