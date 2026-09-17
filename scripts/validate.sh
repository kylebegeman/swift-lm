#!/usr/bin/env bash
set -euo pipefail

# Validates the package, the agent manifest, and the showcase app.
#
# Works with a full Xcode install or with Command Line Tools only. Command Line Tools ship Swift
# Testing outside SwiftPM's default search paths, so the test run points at it explicitly, and the
# iOS showcase build is skipped because it needs Xcode.

developer_dir="$(xcode-select -p 2>/dev/null || true)"
test_flags=()
if [[ "$developer_dir" == */CommandLineTools ]]; then
  test_flags=(
    -Xswiftc -F -Xswiftc "$developer_dir/Library/Developer/Frameworks"
    -Xswiftc -plugin-path -Xswiftc "$developer_dir/usr/lib/swift/host/plugins/testing"
    -Xlinker -F -Xlinker "$developer_dir/Library/Developer/Frameworks"
    -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/Frameworks"
    -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib"
  )
fi

swift build
# The expansion guard keeps empty arrays safe under `set -u` in the bash 3.2 that ships with macOS.
swift test ${test_flags[@]+"${test_flags[@]}"}
jq empty llm/manifest.json

while IFS= read -r documented_path; do
  if [[ ! -e "$documented_path" ]]; then
    echo "Missing documented path from llm/manifest.json: $documented_path" >&2
    exit 1
  fi
done < <(jq -r '.entrypoint, .preferredReadOrder[], .docs[].path' llm/manifest.json | sort -u)

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Skipping showcase generation because xcodegen is not installed."
  exit 0
fi

xcodegen generate --spec Examples/LMShowcase/project.yml

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Skipping the showcase build because Xcode is not selected (developer directory: ${developer_dir:-none})."
  exit 0
fi

xcodebuild \
  -project Examples/LMShowcase/LMShowcase.xcodeproj \
  -scheme LMShowcase \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
