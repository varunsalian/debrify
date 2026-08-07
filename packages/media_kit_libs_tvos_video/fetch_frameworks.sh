#!/bin/bash
# Assemble the tvOS libmpv frameworks into the local plugin package, then
# report which ones actually carry Apple TV slices. A framework that only has
# ios/macos slices links fine for iOS and then fails the tvOS build with a
# confusing "building for tvOS but linking iOS" error, so check up front.
set -u
S=/private/tmp/claude-501/-Users-varunbsalian-Documents-Projects-debrify/af8895c2-5a20-4b07-a105-f5b356dd8d74/scratchpad
SRC=$S/mpvtv
DEST=$S/media_kit_libs_tvos_video/tvos/Frameworks

mkdir -p "$DEST"
cd "$SRC" || exit 1

echo "=== extracting ==="
for z in *.zip; do
  unzip -q -o "$z" -d "$SRC" 2>/dev/null
done

echo "=== slice audit ==="
ok=0; bad=0
for fw in "$SRC"/*.xcframework; do
  name=$(basename "$fw")
  if plutil -p "$fw/Info.plist" 2>/dev/null | grep -q '"SupportedPlatform" => "tvos"'; then
    # Copy only the tvOS-capable ones; shipping ios-only slices into a tvOS
    # pod is what produces the misleading link errors.
    rm -rf "$DEST/$name"
    cp -R "$fw" "$DEST/$name"
    ok=$((ok+1))
  else
    echo "  NO TVOS SLICE: $name"
    bad=$((bad+1))
  fi
done
echo "tvOS-capable: $ok   missing: $bad"
echo "=== dest ==="
ls "$DEST" | wc -l
du -sh "$DEST"
