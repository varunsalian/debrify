# Debrify 2 for Apple TV

Debrify 2 is a separate native tvOS application built from the secured Debrify V1 codebase. It must install beside V1, preserve every V1 safety boundary and playback improvement, and selectively reproduce the current upstream Debrify browsing experience without importing the insecure Flutter networking or credential-storage paths.

## Non-negotiable boundaries

- Default bundle identity: `com.debrify.tv2`; display name: `Debrify 2`. Contributors select their own Apple development team locally.
- V1 remains in `../tvos` and is never replaced by V2 builds.
- Provider credentials and personalized addon routing URLs stay in the V2 Keychain namespace.
- Credential-bearing services require HTTPS; addon/catalog/stream requests reject private-network destinations.
- The unauthenticated UDP remote and setup-transfer features remain absent.
- Playback continues through the secured V1 resolver, embedded player, and optional Infuse handoff.

## V2 experience

- Stremio-style Home with hero artwork, trailers, Continue Watching, Favorites, Playlist, and addon catalog shelves.
- Unified Search with per-engine result groups, source/type filters, sorting, multi-select playlist addition, cloud/IPTV/catalog results, and detailed Torrentio sources on title pages.
- Discover and See All catalog browsing with media filters, sorting, and Stremio `skip` pagination.
- Unified Cloud entry for all supported debrid providers, WebDAV, and transfers.
- Addon marketplace entry with one-click Cinemeta and a secure personalized-addon installation flow.
- Preserved V1 series episodes and thumbnails, source size/codec/release metadata, WebDAV artwork matching, Infuse preference, larger posters, and high-contrast DPAD focus styling.

## Verification gate

Every release must compile the app and test bundle, confirm the generated bundle identity/display name, retain the URL-safety and secure-addon tests, install beside V1, and launch on the target Apple TV before it is called device-verified.
