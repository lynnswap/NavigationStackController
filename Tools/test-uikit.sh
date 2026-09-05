#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 'platform=iOS Simulator,id=<UDID>' [xcodebuild options...]" >&2
    exit 64
fi

destination=$1
shift
repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_package=$(mktemp -d "${TMPDIR:-/tmp}/navigation-stack-tests.XXXXXX")
trap 'rm -rf "$test_package"' EXIT

# The app workspace exposes the library as a dependency scheme without its test action.
# A standalone package context includes the package's test targets and uses the same source files.
for item in Package.swift Sources Tests; do
    ln -s "$repo_root/$item" "$test_package/$item"
done

cd "$test_package"
xcodebuild -scheme NavigationStackController -testPlan NavigationStackController \
    -destination "$destination" "$@" test
