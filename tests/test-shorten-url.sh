#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

export OMARCHY_SHORTEN_URL_CONFIG="$tmp_dir/config.json"
export OMARCHY_SHORTEN_URL_HISTORY="$tmp_dir/history.json"
mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/curl" <<'EOF'
#!/usr/bin/env bash
if printf '%s\n' "$*" | grep -q '/v4/shorten'; then
  printf '{"link":"https://bitly.test/selected"}\n'
else
  printf '{"shorturl":"https://yourls.test/selected"}\n'
fi
EOF
chmod +x "$tmp_dir/bin/curl"
cat >"$tmp_dir/bin/wl-copy" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
EOF
cat >"$tmp_dir/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp_dir/bin/wl-copy" "$tmp_dir/bin/notify-send"
export PATH="$tmp_dir/bin:$PATH"

cat >"$OMARCHY_SHORTEN_URL_CONFIG" <<'EOF'
{
  "defaultProfile": "Branded Bitly",
  "profiles": {
    "Branded Bitly": {
      "type": "bitly",
      "apiUrl": "https://api.bitly.test",
      "accessToken": "token"
    },
    "Legacy Links": {
      "type": "yourls",
      "apiUrl": "https://go.test",
      "signature": "signature"
    }
  }
}
EOF

result=$("$repo_dir/bin/omarchy-shorten-url" https://example.com)
[[ "$result" == "https://bitly.test/selected" ]]

result=$("$repo_dir/bin/omarchy-shorten-url" --profile "Legacy Links" https://example.com)
[[ "$result" == "https://yourls.test/selected" ]]

echo "shortening profile tests passed"
