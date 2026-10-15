#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$project_dir/build"
app_dir="$build_dir/Clamsomnia.app"
architecture="$(uname -m)"
target="$architecture-apple-macosx14.0"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

xcrun swiftc -target "$target" -parse-as-library \
  "$project_dir"/Sources/Shared/*.swift \
  "$project_dir"/Sources/App/*.swift \
  -o "$app_dir/Contents/MacOS/Clamsomnia"

xcrun swiftc -target "$target" \
  -framework Security -framework SystemConfiguration -framework IOKit \
  "$project_dir"/Sources/Shared/*.swift \
  "$project_dir"/Sources/Helper/*.swift \
  -o "$build_dir/com.mytory.Clamsomnia.helper"

if [ -d "$project_dir/Resources/App" ]; then
  ditto "$project_dir/Resources/App" "$app_dir/Contents/Resources"
fi

codesign --force --sign - --timestamp=none "$build_dir/com.mytory.Clamsomnia.helper"
codesign --force --sign - --timestamp=none "$app_dir"

echo "Built $app_dir"
echo "Built $build_dir/com.mytory.Clamsomnia.helper"
