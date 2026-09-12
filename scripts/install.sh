#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
app_source="$project_dir/build/MacDisplaySync.app"
app_target="/Applications/MacDisplaySync.app"

if [[ ! -d "$app_source" ]]; then
  "$project_dir/scripts/build.sh"
fi

pkill -x MacDisplaySync 2>/dev/null || true
for _ in {1..50}; do
  pgrep -x MacDisplaySync >/dev/null || break
  sleep 0.1
done
ditto "$app_source" "$app_target"
xattr -dr com.apple.quarantine "$app_target" 2>/dev/null || true
open "$app_target"

echo "Installed and opened $app_target"
