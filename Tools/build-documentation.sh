#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 OUTPUT_DIRECTORY [HOSTING_BASE_PATH]" >&2
    exit 64
fi

output_dir=$1
hosting_base_path=${2:-}
hosting_base_path=${hosting_base_path%/}
repo_root=$(cd "$(dirname "$0")/.." && pwd)

# Refuse to mix an earlier site's files into a new Pages artifact.
if [[ -e "$output_dir" ]]; then
    echo "Output directory already exists: $output_dir" >&2
    exit 64
fi
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
build_root=$(mktemp -d "${TMPDIR:-/tmp}/navigation-stack-docs.XXXXXX")
trap 'rm -rf "$build_root"' EXIT

# Build the site's entry point with DocC as well. Its links use the same hosting prefix
# as the platform archives, including when Pages is served from a custom domain root.
cp -R "$repo_root/Documentation/NavigationStackController.docc" "$build_root/Documentation.docc"
python3 - "$build_root/Documentation.docc" "$hosting_base_path" <<'PY'
import pathlib
import sys

for page in pathlib.Path(sys.argv[1]).glob("*.md"):
    text = page.read_text()
    for platform in ("uikit", "appkit"):
        text = text.replace(f"](/{platform}/", f"]({sys.argv[2]}/{platform}/")
    page.write_text(text)
PY

xcrun docc convert "$build_root/Documentation.docc" \
    --output-dir "$build_root/Documentation.doccarchive" \
    --hosting-base-path "$hosting_base_path" \
    --fallback-display-name NavigationStackController \
    --fallback-bundle-identifier dev.lynnswap.NavigationStackController.Documentation \
    --warnings-as-errors
cp -R "$build_root/Documentation.doccarchive/." "$output_dir/"
# DocC renders its technology root at /documentation/<name>, not the hosting base URL.
cat > "$output_dir/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta http-equiv="refresh" content="0; url=documentation/navigationstackcontroller/">
<title>NavigationStackController Documentation</title>
<a href="documentation/navigationstackcontroller/">Open documentation</a>
</html>
HTML

for platform in uikit appkit; do
    case "$platform" in
        uikit)
            destination='generic/platform=iOS Simulator'
            configuration_dir=Debug-iphonesimulator
            catalog=UIKit
            ;;
        appkit)
            destination='generic/platform=macOS'
            configuration_dir=Debug
            catalog=AppKit
            ;;
    esac

    xcodebuild docbuild \
        -workspace "$repo_root/NavigationStackController.xcworkspace" \
        -scheme NavigationStackController \
        -configuration Debug \
        -destination "$destination" \
        -derivedDataPath "$build_root/$platform" \
        "DOCC_HOSTING_BASE_PATH=$hosting_base_path/$platform" \
        "OTHER_DOCC_FLAGS=--warnings-as-errors --experimental-documentation-coverage \"$repo_root/Documentation/$catalog.docc\"" \
        CODE_SIGNING_ALLOWED=NO

    # DocC does not warn about missing comments. Check authored public symbols, excluding
    # synthesized conformances without source locations, using the graph DocC actually consumed.
    python3 - "$build_root/$platform" "$platform" <<'PY'
import json
import pathlib
import sys

graphs = list(pathlib.Path(sys.argv[1]).rglob("NavigationStackController.symbols.json"))
if not graphs:
    raise SystemExit("No public symbol graph was generated.")
symbols = {}
for path in graphs:
    for symbol in json.loads(path.read_text())["symbols"]:
        if symbol.get("location"):
            symbols[symbol["identifier"]["precise"]] = symbol
if not symbols:
    raise SystemExit("No authored public symbols were extracted.")
missing = [
    symbol["names"]["title"]
    for symbol in symbols.values()
    if not any(line["text"].strip() for line in symbol.get("docComment", {}).get("lines", []))
]
if missing:
    raise SystemExit("Missing public documentation: " + ", ".join(sorted(missing)))
print(f"{sys.argv[2]}: all {len(symbols)} authored public symbols have documentation.")
PY

    archive="$build_root/$platform/Build/Products/$configuration_dir/NavigationStackController.doccarchive"
    test -f "$archive/documentation/navigationstackcontroller/index.html"
    cp -R "$archive" "$output_dir/$platform"
done

echo "Documentation site: $output_dir"
