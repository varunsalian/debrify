#!/usr/bin/env bash
# Cross-file dead code. `flutter analyze` only sees private members; these two
# checks walk the import graph from lib/ and find unreferenced public ones.
set -euo pipefail
cd "$(dirname "$0")/../.."
dart run dart_code_linter:metrics check-unused-code lib --no-congratulate "$@"
echo
dart run dart_code_linter:metrics check-unused-files lib --no-congratulate "$@"
