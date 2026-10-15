#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -parse-as-library \
  "$project_dir"/Sources/Shared/*.swift \
  "$project_dir"/Tests/PreventionOptionsTests.swift \
  -o "$test_dir/prevention-options-tests"
"$test_dir/prevention-options-tests"
