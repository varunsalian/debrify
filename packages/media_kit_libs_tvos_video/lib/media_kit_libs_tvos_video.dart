/// Dependency-only package: it ships no Dart API. Its entire job is to get
/// libmpv (and its ffmpeg/libass dependencies) linked and embedded into the
/// Apple TV app bundle so `package:media_kit`'s dart:ffi lookup can resolve.
library media_kit_libs_tvos_video;
