#!/bin/sh
set -eu

SOURCE="$1"
DESTINATION="$2"

relpath() {
  current="${2:+$1}"
  target="${2:-$1}"
  target="/${target##/}"
  current="/${current##/}"
  appendix="${target##/}"
  relative=''
  while appendix="${target#"$current"/}"
    [ "$current" != '/' ] && [ "$appendix" = "$target" ]; do
    current="${current%/*}"
    relative="$relative${relative:+/}.."
  done
  relative="$relative${relative:+${appendix:+/}}${appendix#/}"
  echo "$relative"
}

find "$SOURCE" -mindepth 1 -maxdepth 1 -type d | while read -r slice; do
  slug="$(basename "$slice")"
  name="$(echo "$slug" | cut -d '-' -f 1 -f 3)"
  ln -s "$(relpath "$DESTINATION" "$slice")" "$DESTINATION/$name"
done
