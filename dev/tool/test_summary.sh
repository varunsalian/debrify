#!/usr/bin/env bash
# Runs `flutter test` and prints only a compact summary: result counts, then
# each failing test's name with the start of its error. The full JSON report
# stays on disk for when the summary is not enough.
#
# Usage: dev/tool/test_summary.sh [flutter test args/paths...]
# Requires jq for the summary.
set -uo pipefail

report="$(mktemp -t flutter_test_report).json"
flutter test --no-pub -r silent --file-reporter "json:$report" "$@"
status=$?

if ! command -v jq >/dev/null; then
  echo "jq not found; read the JSON report directly." >&2
elif [[ -s "$report" ]]; then
  jq -rs '
    (map(select(.type == "testStart"))
      | map({key: (.test.id | tostring), value: .test.name})
      | from_entries) as $names
    | (map(select(.type == "testDone" and (.hidden | not)))
        | group_by(if .skipped then "skipped" else .result end)
        | map("\(if .[0].skipped then "skipped" else .[0].result end)=\(length)")
        | join(" ")),
      (map(select(.type == "error"))
        | group_by(.testID)[]
        | "FAIL: \($names[(.[0].testID | tostring)])\n\(.[0].error | .[0:600])")
  ' "$report"
fi
echo "exit=$status report=$report"
exit "$status"
