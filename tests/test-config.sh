#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

export OMARCHY_SHORTEN_URL_CONFIG="$tmp_dir/config.json"
helper="$repo_dir/bin/omarchy-shorten-url-config"

assert_eq() {
  [[ "$1" == "$2" ]] || { echo "expected '$2', got '$1'" >&2; exit 1; }
}

config='{"defaultProfile":"Acme Links","profiles":{"Acme Links":{"type":"shlink","apiUrl":"https://links.example","apiKey":"secret"},"Personal":{"type":"yourls","apiUrl":"https://go.example","signature":"sig"}}}'

if "$helper" --list >/dev/null 2>&1; then
  echo "missing config unexpectedly succeeded" >&2
  exit 1
fi

printf '%s\n' '{"type":"shlink","apiUrl":"https://first.example","apiKey":"first-key"}' | "$helper" --save-profile "First Profile"
assert_eq "$("$helper" --get 'First Profile' | jq -r '.apiUrl')" "https://first.example"

"$helper" --save "$config"
[[ "$(stat -c '%a' "$OMARCHY_SHORTEN_URL_CONFIG")" == 600 ]]
assert_eq "$("$helper" --list | jq -r '.[0].name')" "Acme Links"
assert_eq "$("$helper" --get Personal | jq -r '.type')" "yourls"
assert_eq "$("$helper" --get 'Acme Links' | jq -r '.apiKey')" "secret"

printf '%s\n' '{"type":"kutt","apiUrl":"https://kutt.example","apiKey":"key"}' | "$helper" --save-profile "New Kutt"
assert_eq "$("$helper" --get 'New Kutt' | jq -r '.type')" "kutt"
if printf '%s\n' '{"type":"bitly","apiUrl":"https://bitly.example","accessToken":"token"}' | "$helper" --save-profile "New Kutt" >/dev/null 2>&1; then
  echo "profile type mutation unexpectedly succeeded" >&2
  exit 1
fi

printf '%s\n' '{"type":"kutt","apiUrl":"https://new-kutt.example","apiKey":"new-key"}' | "$helper" --save-profile "New Kutt"
assert_eq "$("$helper" --get 'New Kutt' | jq -r '.apiUrl')" "https://new-kutt.example"

"$helper" --set-default "New Kutt"
printf '%s\n' '{"type":"kutt","apiUrl":"https://renamed.example","apiKey":"key"}' | "$helper" --rename-profile "New Kutt" "Renamed Kutt"
assert_eq "$(jq -r .defaultProfile "$OMARCHY_SHORTEN_URL_CONFIG")" "Renamed Kutt"
if "$helper" --get "New Kutt" >/dev/null 2>&1; then
  echo "old profile name still exists after rename" >&2
  exit 1
fi

"$helper" --set-default Personal
assert_eq "$(jq -r .defaultProfile "$OMARCHY_SHORTEN_URL_CONFIG")" "Personal"

"$helper" --delete Personal
assert_eq "$(jq -r .defaultProfile "$OMARCHY_SHORTEN_URL_CONFIG")" "Acme Links"

if "$helper" --save '{"defaultProfile":"Bad","profiles":{"Bad":{"type":"not-a-provider"}}}' >/dev/null 2>&1; then
  echo "invalid provider unexpectedly succeeded" >&2
  exit 1
fi

echo "profile helper tests passed"

cat >"$OMARCHY_SHORTEN_URL_CONFIG" <<'EOF'
{
  "provider": "shlink",
  "shlink": {
    "apiUrl": "https://legacy.example",
    "apiKey": "legacy-key"
  }
}
EOF
assert_eq "$("$helper" --list | jq -r '.[0].name')" "Default"
assert_eq "$("$helper" --get Default | jq -r '.apiUrl')" "https://legacy.example"
