#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_path="/Applications/Clamsomnia.app"
helper_path="/Library/PrivilegedHelperTools/com.mytory.Clamsomnia.helper"
plist_path="/Library/LaunchDaemons/com.mytory.Clamsomnia.helper.plist"

if pgrep -x Clamsomnia >/dev/null; then
  echo "Quit Clamsomnia before installing a new build." >&2
  exit 1
fi

if [ "${1:-}" != "--skip-build" ]; then
  "$project_dir/Scripts/build.sh"
fi
sudo -v

sudo launchctl bootout system/com.mytory.Clamsomnia.helper 2>/dev/null || true
sudo install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
sudo install -o root -g wheel -m 755 \
  "$project_dir/build/com.mytory.Clamsomnia.helper" "$helper_path"
sudo install -o root -g wheel -m 644 \
  "$project_dir/Resources/Helper/com.mytory.Clamsomnia.helper.plist" "$plist_path"
sudo ditto "$project_dir/build/Clamsomnia.app" "$app_path"
sudo chown -R root:wheel "$app_path"
sudo chmod -R go-w "$app_path"
codesign --verify --deep --strict "$app_path"
sudo launchctl bootstrap system "$plist_path"

echo "Installed $app_path"
echo "Open it with: open '$app_path'"
