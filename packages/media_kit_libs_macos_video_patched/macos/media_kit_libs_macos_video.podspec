Pod::Spec.new do |s|
  system('make') || raise('PGS-capable MediaKit frameworks are unavailable')

  s.name             = 'media_kit_libs_macos_video'
  s.version          = '1.1.4'
  s.summary          = 'PGS-capable macOS native libraries for media_kit'
  s.description      = 'Debrify-pinned libmpv and FFmpeg frameworks with common subtitle decoders.'
  s.homepage         = 'https://github.com/media-kit/media-kit'
  s.license          = { :type => 'LGPL-3.0-or-later' }
  s.author           = { 'Debrify' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.vendored_frameworks = 'Frameworks/*.xcframework'
  s.platform         = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
