#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
source_app="$project_dir/build/TouchBarUsageMonitor.app"
target_dir="$HOME/Applications"
target_app="$target_dir/TouchBarUsageMonitor.app"
agent_dir="$HOME/Library/LaunchAgents"
agent_path="$agent_dir/com.local.touchbar-usage-monitor.plist"
label="com.local.touchbar-usage-monitor"

if [[ ! -d "$source_app" ]]; then
  print -u2 "Build missing. Run: make build"
  exit 1
fi

launchctl bootout "gui/$UID/$label" 2>/dev/null || true
for _ in {1..20}; do
  if ! launchctl print "gui/$UID/$label" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

mkdir -p "$target_dir" "$agent_dir"
ditto "$source_app" "$target_app"
cp "$project_dir/Resources/com.local.touchbar-usage-monitor.plist" "$agent_path"
/usr/libexec/PlistBuddy \
  -c "Set :ProgramArguments:0 $target_app/Contents/MacOS/TouchBarUsageMonitor" \
  "$agent_path"
/usr/libexec/PlistBuddy \
  -c "Set :EnvironmentVariables:TUM_ANTIGRAVITY_WORKSPACE $project_dir" \
  "$agent_path"

launchctl bootstrap "gui/$UID" "$agent_path"
launchctl kickstart -k "gui/$UID/$label"

print "Installed: $target_app"
print "Launch at login: enabled"
