#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

export OMARCHY_SHORTEN_URL_CONFIG="$tmp_dir/config.json"
helper="$repo_dir/bin/omarchy-shorten-url-config"
default_config="$tmp_dir/state-home/omarchy-shorten-url/config.json"

assert_eq() {
  [[ "$1" == "$2" ]] || { echo "expected '$2', got '$1'" >&2; exit 1; }
}

config='{"defaultProfile":"Acme Links","profiles":{"Acme Links":{"type":"shlink","apiUrl":"https://links.example","apiKey":"secret"},"Personal":{"type":"yourls","apiUrl":"https://go.example","signature":"sig"}}}'

if "$helper" --list >/dev/null 2>&1; then
  echo "missing config unexpectedly succeeded" >&2
  exit 1
fi

printf '%s\n' '{"type":"bitly","accessToken":"token"}' \
  | env -u OMARCHY_SHORTEN_URL_CONFIG XDG_STATE_HOME="$tmp_dir/state-home" HOME="$tmp_dir/home" "$helper" --save-profile "Default Bitly"
[[ -f "$default_config" ]]
assert_eq "$(jq -r '.profiles["Default Bitly"].type' "$default_config")" "bitly"

printf '%s\n' '{"type":"shlink","apiUrl":"https://first.example","apiKey":"first-key"}' | "$helper" --save-profile "First Profile"
assert_eq "$("$helper" --get 'First Profile' | jq -r '.apiUrl')" "https://first.example"

printf '%s\n' '{"type":"bitly","accessToken":"token"}' | "$helper" --save-profile "Bitly"
assert_eq "$("$helper" --get Bitly | jq -r '.apiUrl // empty')" ""
if printf '%s\n' '{"type":"shlink","apiKey":"missing-url"}' | "$helper" --save-profile "Missing URL" >/dev/null 2>&1; then
  echo "non-Bitly profile without API URL unexpectedly succeeded" >&2
  exit 1
fi

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

history_file="$tmp_dir/state/omarchy-shorten-url/history.json"
export OMARCHY_SHORTEN_URL_HISTORY="$history_file"
printf '%s\n' 'credentials' > "$OMARCHY_SHORTEN_URL_CONFIG"
mkdir -p "$(dirname "$history_file")"
printf '%s\n' 'history' > "$history_file"

if printf 'no\n' | "$helper" --remove-data >/dev/null 2>&1; then
  echo "cleanup cancellation unexpectedly succeeded" >&2
  exit 1
fi
[[ -f "$OMARCHY_SHORTEN_URL_CONFIG" ]]
[[ -f "$history_file" ]]

printf 'yes\n' | "$helper" --remove-data >/dev/null
[[ ! -e "$OMARCHY_SHORTEN_URL_CONFIG" ]]
[[ ! -e "$history_file" ]]

echo "cleanup tests passed"

echo "profile helper tests passed"

# There is a single config dialect: a top-level "profiles" object. A
# document in any other shape is rejected outright, not migrated.
cat >"$OMARCHY_SHORTEN_URL_CONFIG" <<'EOF'
{
  "provider": "shlink",
  "shlink": {
    "apiUrl": "https://not-a-profiles-document.example",
    "apiKey": "key"
  }
}
EOF
chmod 600 "$OMARCHY_SHORTEN_URL_CONFIG"
if "$helper" --list >/dev/null 2>&1; then
  echo "a config without a top-level \"profiles\" object unexpectedly succeeded" >&2
  exit 1
fi

echo "schema rejection tests passed"
