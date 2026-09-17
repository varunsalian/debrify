#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
tv_sdk="$(sed -n 's/^sdk.dir=//p' android/local.properties)"
export PATH="$tv_sdk/platform-tools:$PATH"
tv_serial=""
for candidate in $(adb devices | awk '/^emulator-.*device$/{print $1}'); do
  if adb -s "$candidate" emu avd name | tr -d '\r' | grep -qx debrify_tv; then
    tv_serial="$candidate"
    break
  fi
done
if [[ -z "$tv_serial" ]]; then
  if adb devices | grep -q '^emulator-5554'; then
    echo 'Port 5554 is occupied by another emulator. Stop it or start debrify_tv manually.'
    exit 1
  fi
  nohup "$tv_sdk/emulator/emulator" -avd debrify_tv -port 5554 > /tmp/debrify-tv-emulator.log 2>&1 &
  tv_serial=emulator-5554
fi
adb -s "$tv_serial" wait-for-device
for attempt in {1..120}; do
  [[ "$(adb -s "$tv_serial" shell getprop sys.boot_completed | tr -d '\r')" == 1 ]] && break
  sleep 1
done
[[ "$(adb -s "$tv_serial" shell getprop sys.boot_completed | tr -d '\r')" == 1 ]] || { echo 'TV boot timed out'; exit 1; }
adb -s "$tv_serial" shell monkey -p com.debrify.app 1 > /dev/null
export DEBRIFY_TV_SERIAL="$tv_serial"
if ! curl -fsS http://127.0.0.1:18766/ 2>/dev/null | grep -q '<title>Debrify TV remote</title>'; then
  (sleep 1; open http://127.0.0.1:18766/) &
  echo 'Keep this terminal open for the TV remote. Ctrl-C stops the remote only.'
  exec node tool/tv_remote.mjs
fi
open http://127.0.0.1:18766/
echo 'TV ready. Remote: http://127.0.0.1:18766/'
