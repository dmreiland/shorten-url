#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
panel="$repo_dir/Panel.qml"
settings="$repo_dir/ProviderSettings.qml"
prompt="$repo_dir/UrlPrompt.qml"
bar_widget="$repo_dir/BarWidget.qml"
service="$repo_dir/Service.qml"
manifest="$repo_dir/manifest.json"

assert_masked_api_key() {
    local file=$1
    awk '
        /Ui\.TextField[[:space:]]*\{/ { in_field = 1; has_key = 0; masked = 0 }
        /placeholderText: "API key"/ { has_key = 1; seen = 1 }
        /echoMode: TextInput\.Password/ { masked = 1 }
        /^[[:space:]]*}/ {
            if (in_field && has_key && !masked) exit 1
            in_field = 0
        }
        END { if (!seen) exit 1 }
    ' "$file"
}

grep -q 'ProviderSettings' "$panel"
grep -q 'settingsButton' "$panel"
grep -q 'urlField.text = ""' "$panel"
grep -q 'isProviderUrl' "$panel"
grep -q 'historyCopier.command' "$panel"
grep -q 'function submitUrl()' "$panel"
grep -q 'root.submitUrl()' "$panel"
grep -q 'focusUrlField()' "$panel"
if grep -q 'providerDropdown' "$panel"; then
    echo "main panel still has a duplicate provider selector" >&2
    exit 1
fi
if grep -q 'text: provider' "$panel"; then
    echo "recent-link rows still display the provider" >&2
    exit 1
fi
grep -q 'text: "Shorten URL"' "$panel"
grep -q 'text: "Recent links"' "$panel"
test -f "$settings"
assert_masked_api_key "$settings"
if grep -q 'height: Math.min(Style.space(620)' "$settings"; then
    echo "provider settings card still uses a fixed height" >&2
    exit 1
fi
grep -q 'implicitHeight' "$settings"
grep -q 'Default' "$settings"
if grep -q 'label: "Profile"' "$settings"; then
    echo "provider settings still duplicates the active profile dropdown" >&2
    exit 1
fi
grep -q 'profileList' "$settings"
grep -q 'profileRow' "$settings"
assert_masked_api_key "$panel"
test -f "$prompt"
test -f "$service"
grep -q '^import Quickshell.Io$' "$service"
grep -q 'IpcHandler' "$service"
grep -q 'target: root.moduleName' "$service"
grep -q 'summonBarWidget' "$service"
grep -q 'hideBarWidget' "$service"
grep -q 'isBarWidgetOpen' "$service"
grep -q '"panel"' "$manifest"
grep -q '"service"' "$manifest"
grep -q '"panel": "UrlPrompt.qml"' "$manifest"
grep -q '"service": "Service.qml"' "$manifest"
grep -q 'anchors.centerIn: parent' "$prompt"
grep -q 'focusedScreenName' "$prompt"
grep -q 'screen: root.promptScreen' "$prompt"
grep -q 'function applyClipboardText' "$prompt"
grep -q 'function submitUrl()' "$prompt"
grep -q 'onAccepted: root.submitUrl()' "$prompt"
sed -n '/function open(/,/function close(/p' "$prompt" | grep -q 'urlField.text = ""'

echo "panel contract tests passed"
