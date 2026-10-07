#!/bin/bash
set -euo pipefail

app_path="/Applications/Clamsomnia.app"
helper_path="/Library/PrivilegedHelperTools/com.mytory.Clamsomnia.helper"
plist_path="/Library/LaunchDaemons/com.mytory.Clamsomnia.helper.plist"

if pgrep -x Clamsomnia >/dev/null; then
  echo "Quit Clamsomnia before uninstalling." >&2
  exit 1
fi

if [ -x "$app_path/Contents/MacOS/Clamsomnia" ]; then
  "$app_path/Contents/MacOS/Clamsomnia" --unregister-login
fi

sudo -v
sudo launchctl bootout system/com.mytory.Clamsomnia.helper 2>/dev/null || true
if [ -x "$helper_path" ]; then
  sudo "$helper_path" --restore
fi
sudo rm -f "$plist_path" "$helper_path"
sudo rm -rf "$app_path"

echo "Clamsomnia was removed. User settings remain in macOS preferences."
