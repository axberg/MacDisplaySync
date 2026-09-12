#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
app_dir="$project_dir/build/MacDisplaySync.app"

"$project_dir/scripts/build.sh"
plutil -lint "$app_dir/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app_dir"

if [[ $(uname -m) == arm64 ]]; then
  sensor_output=$("$app_dir/Contents/Resources/monitor-sensor")
  display_output=$("$app_dir/Contents/Resources/monitor-ddc" list)

  printf 'Sensor probe: %s\n' "$sensor_output"
  printf 'DDC displays: %s\n' "$display_output"
else
  echo "Skipping hardware probes: arm64 Mac required"
fi

if git -C "$project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$project_dir" diff --check
fi

echo "Checks passed (read-only)"
