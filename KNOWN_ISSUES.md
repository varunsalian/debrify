# Known Issues

## Video Player Crash on Rapid Navigation

**Symptom**: App crashes with "Callback invoked after it has been deleted" when:
1. Pressing Next button multiple times rapidly
2. Exiting video player (Back button)
3. Immediately opening another video

**Root Cause**: 
- FFI callbacks from media_kit/libmpv continue executing on native threads
- Dart VM disposes the context before native callbacks complete
- Creating a new player instance before cleanup triggers the crash

**Workarounds**:
1. **Wait 1 second** after pressing Back before opening another video
2. Avoid rapid Next/Previous button presses (wait for video to start playing)
3. Use playlist autoplay instead of manual navigation when possible

**Technical Details**:
- Error occurs in `mpv/opener` native thread
- FFI callback attempts to access deleted Dart context
- Issue is in media_kit package, not application code

**Status**: 
- Temporary mitigation: Added 500ms delay in `_handleBack()`
- Permanent fix: Requires update to media_kit package or upstream libmpv changes
- Issue has been reported to media_kit maintainers

**Related Code**:
- `lib/screens/video_player_screen.dart` - `_handleBack()` method
- Uses `_player.dispose()` with delay to allow FFI cleanup
