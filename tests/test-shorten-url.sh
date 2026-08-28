#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

export OMARCHY_SHORTEN_URL_CONFIG="$tmp_dir/config.json"
export OMARCHY_SHORTEN_URL_HISTORY="$tmp_dir/history.json"
export CURL_ARGS_CAPTURE="$tmp_dir/curl-args"
export CURL_CONFIG_CAPTURE="$tmp_dir/curl-config"
mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$CURL_ARGS_CAPTURE"
if [[ -r /proc/$$/fd/3 ]]; then
  cat <&3 > "$CURL_CONFIG_CAPTURE"
else
  : > "$CURL_CONFIG_CAPTURE"
fi
if grep -Eq '^(silent|show-error|fail) = "true"$' "$CURL_CONFIG_CAPTURE"; then
  echo 'curl: option --config: had unsupported trailing garbage' >&2
  exit 2
fi
if [[ "${CURL_OVERSIZE:-0}" == 1 ]]; then
  head -c 65537 /dev/zero | tr '\0' x
  exit 0
fi
if grep -q '/api/v2/action/shorten' "$CURL_CONFIG_CAPTURE"; then
  printf 'https://polr.test/selected\n'
elif grep -q '/v4/shorten' "$CURL_CONFIG_CAPTURE"; then
  printf '{"link":"https://bitly.test/selected"}\n'
elif grep -q '/rest/v3/short-urls' "$CURL_CONFIG_CAPTURE"; then
  printf '{"shortUrl":"https://shlink.test/selected"}\n'
elif grep -q '/api/v2/links' "$CURL_CONFIG_CAPTURE"; then
  printf '{"link":"https://kutt.test/selected"}\n'
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
grep -Fxq 'url = "https://api-ssl.bitly.com/v4/shorten"' "$CURL_CONFIG_CAPTURE"
! tr '\0' '\n' < "$CURL_ARGS_CAPTURE" | grep -Fq 'token'
grep -Fxq 'header = "Authorization: Bearer token"' "$CURL_CONFIG_CAPTURE"

result=$("$repo_dir/bin/omarchy-shorten-url" --profile "Legacy Links" https://example.com)
[[ "$result" == "https://yourls.test/selected" ]]
grep -Fxq 'url = "https://go.test/yourls-api.php"' "$CURL_CONFIG_CAPTURE"
! tr '\0' '\n' < "$CURL_ARGS_CAPTURE" | grep -Fq 'signature'
grep -Fxq 'data-urlencode = "signature=signature"' "$CURL_CONFIG_CAPTURE"

cat >"$OMARCHY_SHORTEN_URL_CONFIG" <<'EOF'
{
  "profiles": {
    "Username Links": {
      "type": "yourls",
      "apiUrl": "https://go.test",
      "username": "yourls-user",
      "password": "yourls-password"
    }
  }
}
EOF

result=$("$repo_dir/bin/omarchy-shorten-url" --profile "Username Links" https://example.com)
[[ "$result" == "https://yourls.test/selected" ]]
! tr '\0' '\n' < "$CURL_ARGS_CAPTURE" | grep -Fq 'yourls-user'
! tr '\0' '\n' < "$CURL_ARGS_CAPTURE" | grep -Fq 'yourls-password'
grep -Fxq 'data-urlencode = "username=yourls-user"' "$CURL_CONFIG_CAPTURE"
grep -Fxq 'data-urlencode = "password=yourls-password"' "$CURL_CONFIG_CAPTURE"

cat >"$OMARCHY_SHORTEN_URL_CONFIG" <<'EOF'
{
  "profiles": {
    "Polr": {
      "type": "polr",
      "apiUrl": "https://polr.test",
      "apiKey": "polr-secret"
    }
  }
}
EOF

# --profile selects the configured provider profile.
result=$("$repo_dir/bin/omarchy-shorten-url" --profile Polr https://example.com)
[[ "$result" == "https://polr.test/selected" ]]
! tr '\0' '\n' < "$CURL_ARGS_CAPTURE" | grep -Fq 'polr-secret'
! tr '\0' '\n' < "$CURL_ARGS_CAPTURE" | grep -Fq -- '-G'
grep -Fxq 'request = "POST"' "$CURL_CONFIG_CAPTURE"
grep -Fxq 'data-urlencode = "key=polr-secret"' "$CURL_CONFIG_CAPTURE"
grep -Fxq 'data-urlencode = "url=https://example.com"' "$CURL_CONFIG_CAPTURE"
grep -Fxq 'connect-timeout = "5"' "$CURL_CONFIG_CAPTURE"
grep -Fxq 'max-time = "20"' "$CURL_CONFIG_CAPTURE"
grep -Fxq 'max-filesize = "65536"' "$CURL_CONFIG_CAPTURE"
! grep -Fq '?key=polr-secret' "$CURL_CONFIG_CAPTURE"

# Exercise the provider-response size cap with an explicit profile.
cat >"$OMARCHY_SHORTEN_URL_CONFIG" <<'EOF'
{
  "profiles": {
    "Polr": {
      "type": "polr",
      "apiUrl": "https://polr.test",
      "apiKey": "polr-secret"
    }
  }
}
EOF
if CURL_OVERSIZE=1 "$repo_dir/bin/omarchy-shorten-url" --profile Polr https://example.com >/dev/null 2>&1; then
  echo "oversized provider response unexpectedly succeeded" >&2
  exit 1
fi

cat >"$OMARCHY_SHORTEN_URL_CONFIG" <<'EOF'
{
  "profiles": {
    "Shlink": {
      "type": "shlink",
      "apiUrl": "https://shlink.test",
      "apiKey": "shlink-secret"
    },
    "Kutt": {
      "type": "kutt",
      "apiUrl": "https://kutt.test",
      "apiKey": "kutt-secret"
    }
  }
}
EOF

for profile_result in "Shlink shlink-secret https://shlink.test/selected" "Kutt kutt-secret https://kutt.test/selected"; do
  read -r profile secret expected <<<"$profile_result"
  result=$("$repo_dir/bin/omarchy-shorten-url" --profile "$profile" https://example.com)
  [[ "$result" == "$expected" ]]
  ! tr '\0' '\n' < "$CURL_ARGS_CAPTURE" | grep -Fq "$secret"
  grep -Fq "$secret" "$CURL_CONFIG_CAPTURE"
done

echo "shortening profile tests passed"
