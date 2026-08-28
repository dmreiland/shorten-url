#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

source "$repo_dir/bin/omarchy-shorten-url-lib"

# --- read_bounded_file refuses to follow a symlink --------------------------
# O_NOFOLLOW makes this rejection atomic with open().
printf '{"ok":1}' > "$tmp_dir/real.json"
ln -s real.json "$tmp_dir/link.json"
if read_bounded_file "$tmp_dir/link.json" >/dev/null 2>&1; then
  echo "reading a symlinked path unexpectedly succeeded" >&2
  exit 1
fi

# --- a concurrent regular-file/symlink swap never leaks the target ---------
# ln -f swaps the directory entry without writing through the symlink.
secret_file="$tmp_dir/secret.json"
printf '{"secret":true}' > "$secret_file"
plain_source="$tmp_dir/plain_source.json"
printf '{"ok":1}' > "$plain_source"
victim="$tmp_dir/victim.json"
ln -f "$plain_source" "$victim"

racer_pid=""
racer() {
  local end=$((SECONDS + 2))
  while (( SECONDS < end )); do
    ln -f "$plain_source" "$victim" 2>/dev/null
    ln -sfn "$secret_file" "$victim" 2>/dev/null
  done
}
racer &
racer_pid=$!

leaked=0
for _ in $(seq 1 500); do
  out="$(read_bounded_file "$victim" 2>/dev/null || true)"
  if [[ "$out" == *secret* ]]; then
    leaked=1
    break
  fi
done
kill "$racer_pid" 2>/dev/null || true
wait "$racer_pid" 2>/dev/null || true
[[ "$(cat "$secret_file")" == '{"secret":true}' ]] || { echo "the race corrupted the secret file itself (test bug, not a product bug)" >&2; exit 1; }
(( leaked == 0 )) || { echo "read_bounded_file returned symlink-target content during a concurrent path swap" >&2; exit 1; }

# --- a FIFO is rejected near-instantly by O_NONBLOCK ------------------------
mkfifo "$tmp_dir/fifo.json"
start_ns=$(date +%s%N)
if read_bounded_file "$tmp_dir/fifo.json" >/dev/null 2>&1; then
  echo "reading a FIFO unexpectedly succeeded" >&2
  exit 1
fi
elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
# This should take milliseconds, not approach the timeout backstop.
(( elapsed_ms < 1000 )) || { echo "read_bounded_file took ${elapsed_ms}ms on a FIFO; expected a near-instant O_NONBLOCK rejection" >&2; exit 1; }

# --- a file exactly at the byte ceiling is accepted in full -----------------
head -c 100 /dev/zero | tr '\0' 'x' > "$tmp_dir/exact.json"
out=$(READ_FILE_MAX_BYTES=100 read_bounded_file "$tmp_dir/exact.json")
[[ "${#out}" == 100 ]]

# --- one byte over the ceiling is rejected, never truncated -----------------
# The helper reads MAX+1 bytes instead of trusting a size check.
head -c 101 /dev/zero | tr '\0' 'x' > "$tmp_dir/over.json"
if out=$(READ_FILE_MAX_BYTES=100 read_bounded_file "$tmp_dir/over.json" 2>/dev/null); then
  echo "a file one byte over the ceiling unexpectedly succeeded" >&2
  exit 1
fi
[[ -z "${out:-}" ]] || { echo "an oversized file was truncated and served instead of rejected" >&2; exit 1; }

# --- a normal regular file is still read correctly --------------------------
[[ "$(read_bounded_file "$tmp_dir/real.json")" == '{"ok":1}' ]]

# --- a regular-file read error fails closed ---------------------------------
# /proc/self/mem is regular but returns an error when read this way.
if out=$(read_bounded_file /proc/self/mem 2>/dev/null); then
  echo "a regular-file read error unexpectedly succeeded" >&2
  exit 1
fi
[[ -z "${out:-}" ]] || { echo "a regular-file read error returned partial data" >&2; exit 1; }

# --- --credential requires ownership and tightens a loose mode --------------
chmod 644 "$tmp_dir/real.json"
[[ "$(read_bounded_file "$tmp_dir/real.json" --credential 2>/dev/null)" == '{"ok":1}' ]]
[[ "$(stat -c '%a' "$tmp_dir/real.json")" == "600" ]]

# --- security ceilings can only be lowered by the environment, never raised
( export READ_FILE_MAX_BYTES=999999999; source "$repo_dir/bin/omarchy-shorten-url-lib"; [[ "$READ_FILE_MAX_BYTES" == 65536 ]] )
( export JSON_MAX_ITEMS=999999999; source "$repo_dir/bin/omarchy-shorten-url-lib"; [[ "$JSON_MAX_ITEMS" == 200 ]] )
( export READ_FILE_MAX_BYTES=10; source "$repo_dir/bin/omarchy-shorten-url-lib"; [[ "$READ_FILE_MAX_BYTES" == 10 ]] )

# --- assert_json_limits rejects shapes that fit the byte ceiling but are
# --- pathological to walk (deep nesting, huge strings, huge item counts) ---
printf '{"defaultProfile":"a","profiles":{"a":{"type":"bitly","accessToken":"tok"}}}' | assert_json_limits

deep=$(printf '['%.0s {1..20}; printf '1'; printf ']'%.0s {1..20})
if printf '%s' "$deep" | assert_json_limits; then
  echo "deeply nested document unexpectedly passed shape limits" >&2
  exit 1
fi

huge_string="$(jq -n --arg s "$(head -c 20000 /dev/zero | tr '\0' 'a')" '{x:$s}')"
if printf '%s' "$huge_string" | assert_json_limits; then
  echo "oversized string field unexpectedly passed shape limits" >&2
  exit 1
fi

many_items="$(jq -n '[range(500)] | {p: (reduce .[] as $i ({}; .[$i|tostring] = $i))}')"
if printf '%s' "$many_items" | assert_json_limits; then
  echo "document with too many items unexpectedly passed shape limits" >&2
  exit 1
fi

# --- assert_json_shape enforces the expected top-level container ----------
printf '{"a":1}' | assert_json_shape object
printf '[{"a":1}]' | assert_json_shape array

if printf '"just a string"' | assert_json_shape object; then
  echo "a bare scalar unexpectedly passed the object shape check" >&2
  exit 1
fi
if printf '{"not":"an array"}' | assert_json_shape array; then
  echo "a top-level object unexpectedly passed the array shape check" >&2
  exit 1
fi
if printf '[1,2,3]' | assert_json_shape array; then
  echo "an array of non-objects unexpectedly passed the array shape check" >&2
  exit 1
fi
if printf '42' | assert_json_shape array; then
  echo "a bare scalar unexpectedly passed the array shape check" >&2
  exit 1
fi

# --- end to end: the real config helper refuses a symlinked config file ----
export OMARCHY_SHORTEN_URL_CONFIG="$tmp_dir/config-link.json"
printf '{"defaultProfile":"Bitly","profiles":{"Bitly":{"type":"bitly","accessToken":"tok"}}}' > "$tmp_dir/config-target.json"
chmod 600 "$tmp_dir/config-target.json"
ln -s config-target.json "$tmp_dir/config-link.json"
if "$repo_dir/bin/omarchy-shorten-url-config" --list >/dev/null 2>&1; then
  echo "omarchy-shorten-url-config unexpectedly followed a symlinked config" >&2
  exit 1
fi
unset OMARCHY_SHORTEN_URL_CONFIG

# --- oversized history degrades to [] ---------------------------------------
export OMARCHY_SHORTEN_URL_CONFIG="$tmp_dir/config.json"
export OMARCHY_SHORTEN_URL_HISTORY="$tmp_dir/history.json"
printf '{"defaultProfile":"Bitly","profiles":{"Bitly":{"type":"bitly","accessToken":"tok"}}}' > "$OMARCHY_SHORTEN_URL_CONFIG"
chmod 600 "$OMARCHY_SHORTEN_URL_CONFIG"
python3 -c 'import json; print(json.dumps([{"shortUrl":"https://x/"+str(i)} for i in range(20000)]))' > "$OMARCHY_SHORTEN_URL_HISTORY" 2>/dev/null \
  || perl -MJSON::PP -e 'print encode_json([map {{shortUrl=>"https://x/$_"}} 1..20000])' > "$OMARCHY_SHORTEN_URL_HISTORY"
[[ "$("$repo_dir/bin/omarchy-shorten-url" --history)" == "[]" ]]

# --- invalid history shape also degrades to [] ------------------------------
printf '{"shortUrl":"not-an-array"}' > "$OMARCHY_SHORTEN_URL_HISTORY"
[[ "$("$repo_dir/bin/omarchy-shorten-url" --history)" == "[]" ]]

echo "file safety tests passed"
