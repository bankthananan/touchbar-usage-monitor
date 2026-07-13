#!/bin/zsh
set -euo pipefail

target_app="$HOME/Applications/TouchBarUsageMonitor.app"
agent_path="$HOME/Library/LaunchAgents/com.local.touchbar-usage-monitor.plist"
label="com.local.touchbar-usage-monitor"

launchctl bootout "gui/$UID/$label" 2>/dev/null || true
rm -f "$agent_path"
rm -rf "$target_app"

print "Touch Bar Usage Monitor was removed."
