#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${DEBRIFY_BUILD_MODE:-release}"
UPLOAD=true
CLEAN=false
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive:}"
RCLONE_DEST_DIR="${RCLONE_DEST_DIR:-}"

die() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

remaining_args=()
for arg in "$@"; do
  case "${arg}" in
    --upload) UPLOAD=true ;;
    --no-upload) UPLOAD=false ;;
    --clean) CLEAN=true ;;
    --no-clean) CLEAN=false ;;
    --debug) MODE=debug ;;
    --profile) MODE=profile ;;
    --release) MODE=release ;;
    *) remaining_args+=("${arg}") ;;
  esac
done
set -- "${remaining_args[@]+"${remaining_args[@]}"}"

case "${MODE}" in
  debug|profile|release) ;;
  *) die "MODE must be debug, profile, or release" ;;
esac

cd "${ROOT}"

if [[ "${CLEAN}" == "true" ]]; then
  printf '[..] flutter clean ...\n'
  flutter clean >/dev/null
  printf '[..] flutter pub get ...\n'
  flutter pub get >/dev/null
fi

printf '[..] flutter build apk --%s ...\n' "${MODE}"
flutter build apk "--${MODE}" "$@"

apk_path="${ROOT}/build/app/outputs/flutter-apk/app-${MODE}.apk"
[[ -f "${apk_path}" ]] || die "APK not found at ${apk_path}"
size="$(du -h "${apk_path}" | cut -f1)"
printf '[ok] APK built: %s (%s)\n' "${apk_path}" "${size}"

if [[ "${UPLOAD}" == "true" ]]; then
  command -v rclone >/dev/null 2>&1 || die "rclone not installed. brew install rclone && rclone config"
  rclone listremotes 2>/dev/null | grep -q "^${RCLONE_REMOTE}$" \
    || die "rclone remote ${RCLONE_REMOTE} not configured. Run: rclone config"

  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  sha="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
  ts="$(date +%Y%m%d-%H%M)"
  safe_branch="${branch//\//-}"
  upload_name="debrify-${MODE}-${safe_branch}-${ts}-${sha}.apk"
  upload_dest="${RCLONE_REMOTE}${RCLONE_DEST_DIR}"

  printf '[..] Uploading %s to %s ...\n' "${upload_name}" "${upload_dest}"
  rclone copyto --progress --stats=15s --stats-one-line \
    "${apk_path}" "${upload_dest}${upload_name}" \
    || die "rclone upload failed"
  printf '[ok] Uploaded as %s\n' "${upload_name}"

  share_link="$(rclone link "${upload_dest}${upload_name}" 2>/dev/null || true)"
  if [[ -n "${share_link}" ]]; then
    printf '[ok] Share link: %s\n' "${share_link}"
  fi
fi
