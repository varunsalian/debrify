#!/bin/bash
# Theming-surface measurement. No args: measures every surface in
# tool/theme_surface_manifest.txt. With args: <label> <files...> ad hoc.
#
# `sites` = Color(0x + Colors.* + withValues. RELATIVE SIZING ONLY — it
# double-counts Colors.white.withValues(...) and misses withOpacity and
# Theme.of(...).colorScheme.*. Good enough to rank surfaces, not to price one.
set -u
measure() {
  local label="$1"; shift
  local files; files=$(ls $@ 2>/dev/null)
  [ -z "$files" ] && { printf "%-22s (no files)\n" "$label"; return; }
  printf "%-22s %3s files %7s lines %5s sites\n" "$label" \
    "$(echo "$files" | wc -l | tr -d ' ')" \
    "$(cat $files | wc -l | tr -d ' ')" \
    "$(cat $files | grep -oE 'Color\(0x|Colors\.[a-zA-Z]+|withValues' | wc -l | tr -d ' ')"
}
if [ $# -gt 0 ]; then measure "$@"; exit; fi
cd "$(dirname "$0")/.." || exit 1
while IFS= read -r line; do
  case "$line" in ''|\#*) continue;; esac
  measure "${line%% =*}" ${line#*= }
done < tool/theme_surface_manifest.txt
