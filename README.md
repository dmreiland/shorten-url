# omarchy-shorten-url

An [Omarchy Quattro](https://omarchyplugins.com/develop.html) plugin that shortens URLs using
a self-hosted or cloud-hosted URL shortener: **YOURLS**, **Shlink**, **Kutt**, **Polr**, or **Bitly**.

## Setup

1. Create the state directory and copy the config template there, then fill in credentials for the provider profiles you use:

   ```bash
   mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-shorten-url"
   cp config.example.json "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-shorten-url/config.json"
   ```

   The config file holds API keys/passwords and is permission-tightened to `600` (owner read/write only) on every run. Each profile has a user-defined name and an immutable provider `type`. The panel can add, edit, rename, delete, and select the default profile.

2. Install the plugin:

   ```bash
   omarchy plugin add https://github.com/dmreiland/shorten-url.git --enable
   ```

   or clone it directly into `~/.config/omarchy/plugins/io.github.dmreiland.shorten-url/`.

3. Validate:

   ```bash
   omarchy plugin validate ~/.config/omarchy/plugins/io.github.dmreiland.shorten-url
   ```

## Remove the plugin and its data

Remove the plugin with the Omarchy CLI, then remove its stored provider credentials and URL
history. The cleanup command asks for explicit confirmation and does not remove the plugin source:

```bash
bin/omarchy-shorten-url-config --remove-data
omarchy plugin remove io.github.dmreiland.shorten-url
```

Run the cleanup helper before removing the plugin, while its source is still available. It removes
`${XDG_STATE_HOME:-~/.local/state}/omarchy-shorten-url/config.json` and `history.json`.

## Using the script standalone

```bash
bin/omarchy-shorten-url                      # shorten whatever is on the clipboard
bin/omarchy-shorten-url https://example.com  # shorten an explicit URL
bin/omarchy-shorten-url --profile "Acme Links" https://example.com
```

On success it prints the shortened URL, copies it to the clipboard (`wl-copy`), sends a desktop
notification if `notify-send` is available, and records the result in a history file. On failure
it prints an error to stderr and exits non-zero.

```bash
bin/omarchy-shorten-url --history        # last 5 shortened URLs, most recent first, as JSON
bin/omarchy-shorten-url --history 10     # override the count
bin/omarchy-shorten-url --copy "text"    # copy arbitrary text to the clipboard
```

History is stored at `${XDG_STATE_HOME:-~/.local/state}/omarchy-shorten-url/history.json`
(override with `$OMARCHY_SHORTEN_URL_HISTORY`), capped at the 5 most recent entries, and
permission-tightened to `600` the same way `config.json` is. The panel shows this list under
"Recent" and refreshes it after every successful shorten; clicking an entry re-copies it to the
clipboard. A successful submission clears the input field.

## Open the URL shortening popover

A URL entry popover can be summoned through the Omarchy shell:

```bash
omarchy-shell shell summon io.github.dmreiland.shorten-url '{}'
```

## Open the bar panel

The full panel attached to the Shorten URL bar widget can be opened or toggled through its direct
IPC target. It is routed to the active display:

```bash
omarchy-shell io.github.dmreiland.shorten-url toggle
```

## Provider notes

| Provider | Auth | Endpoint used |
| --- | --- | --- |
| YOURLS | `signature`, or `username`+`password` | `POST {apiUrl}/yourls-api.php` (`action=shorturl`) |
| Shlink | `X-Api-Key` header | `POST {apiUrl}/rest/v3/short-urls` |
| Kutt | `X-API-KEY` header | `POST {apiUrl}/api/v2/links` |
| Polr | `key` POST parameter | `POST {apiUrl}/api/v2/action/shorten` |
| Bitly | `Authorization: Bearer` header | `POST https://api-ssl.bitly.com/v4/shorten` |

## Security notes

`config.json` and `history.json` hold plaintext credentials and URL history; the script
auto-tightens both to `600` on every run. User input (URLs, profile names, and provider selection)
is validated and passed without shell interpolation. Provider credentials and complete request
data are supplied to curl through a private file descriptor rather than command-line arguments,
so they are not exposed in the process list. Every provider request has a 5-second connection
timeout and 20-second overall timeout, and provider responses are capped at 64 KiB before JSON
parsing. `config.json` has exactly one shape: a top-level `profiles` object; both scripts validate it
against the same schema (`canonicalize_config`/`assert_config_schema` in `bin/omarchy-shorten-url-lib`)
before trusting anything in it.

Both `bin/omarchy-shorten-url` and `bin/omarchy-shorten-url-config` read `config.json`/`history.json`
through the shared `bin/omarchy-shorten-url-lib` helper, which shells out to the `bin/omarchy-shorten-url-safe-read`
Perl helper for the actual open — Bash's own redirection can't request `O_NOFOLLOW`/`O_NONBLOCK`, so
the helper opens with both flags in one syscall (refusing a symlink and never blocking on a FIFO),
verifies it opened a regular file it owns via `fstat` on the descriptor, and reads at most 64 KiB,
rejecting outright rather than truncating if that's exceeded. All four files (`omarchy-shorten-url`,
`omarchy-shorten-url-config`, `omarchy-shorten-url-lib`, `omarchy-shorten-url-safe-read`) must stay
together for the plugin to run; **`perl` is a required runtime dependency** alongside `jq` and `curl`.
