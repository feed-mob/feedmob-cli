# FeedMob CLI (`fm`)

`fm` is the command-line interface for FeedMob services. It manages isolated
credentials for Pixel, Time Off, Femini, Pages, and FeedMob Workspace, verifies authentication, and issues
safe, service-specific API requests — with stable JSON output designed for scripts and
automation.

```text
fm doctor
fm version
fm pixel auth login [--token-stdin]
fm pixel auth status
fm pixel auth logout
fm pixel request get <path> [--raw]
fm time-off auth login [--token-stdin]
fm time-off auth status
fm time-off auth logout
fm time-off request put <path> --json-file <file>
fm time-off request get <path>
fm femini auth login [--token-stdin]
fm femini auth status
fm femini auth logout
fm femini request get <path>
fm pages auth login [--token-stdin]
fm pages auth status
fm pages auth logout
fm pages list [filters]
fm pages show <owner> <slug>
fm pages stats
fm pages publish --owner <owner> --html-file <file> [options]
fm pages update <page-id> [options]
fm pages share enable <page-id> [--rotate]
fm pages share revoke <page-id>
fm pages asset upload <image-file>
fm pages request get <path>
fm workspace auth login [--token-stdin]
fm workspace auth status
fm workspace auth logout
fm workspace openapi
fm workspace request get <api-v1-path>
```

## Installation

### Homebrew (macOS and Linux)

```sh
brew tap feed-mob/tap https://github.com/feed-mob/feedmob-cli.git
brew install feed-mob/tap/fm
```

Prebuilt binaries ship for macOS arm64/x86_64 and Linux arm64/x86_64:

- macOS 11+ on Apple Silicon, macOS 10.12+ on Intel (built and tested on
  macOS 15 runners);
- GNU/glibc >= 2.35 on Linux, i.e. Ubuntu 22.04 or newer; Alpine/musl and
  Windows are not supported.

No Ruby installation is required. On first run the binary downloads its ~11 MB
runtime image once (SHA-256 verified, cached in `~/.tebako/runtimes/`), so
the first invocation needs access to github.com; `TEBAKO_RUNTIME_MIRROR`
(https or file://) can point at an internal mirror.

Upgrading or uninstalling the formula never touches stored credentials; run
`fm <service> auth logout` first if you want them removed.

### From source (development)

Requires Ruby 3.2+:

```sh
bundle install
make install-local
export PATH="$HOME/.local/bin:$PATH"
fm version
```

## Usage

`fm doctor` checks each configured service against its identity endpoint and
reports what still needs configuration:

```sh
fm doctor
fm pixel request get /api/v1/cli/me
```

`request get` only accepts relative paths starting with a single `/`;
absolute URLs and `//host` paths are rejected so tokens can never leak to an
unconfigured host. Only GET requests are exposed.

Pixel paths are relative to the configured base URL, which already ends in
`/rails`. When copying a path from the Pixel API documentation, remove its
leading `/rails`. Use `--json` to read the response under `data.response`, or
`--raw` to write the exact response body to stdout (for example, redirect a CSV
export to a file). `--raw` and `--json` cannot be combined. Raw requests still
report API errors and exit nonzero; check the exit status before using an export.
A shell redirect can create or truncate the destination even when the request fails.

Pixel logout removes locally stored credentials even when remote revocation
fails. Such failures retain a nonzero exit status; JSON error details include
`local_removed` and `remote_revoked`. Environment credentials cannot be removed
by the CLI: unset `FEEDMOB_PIXEL_TOKEN` yourself. If revocation failed due to a
network or permission error, the remote token may remain active.

Time Off journal updates use the existing `request` command. Write the JSON
request body to a file, then call the documented upsert endpoint; it always
writes to the user represented by the configured Time Off token:

```sh
printf '%s' '{"content":"Completed API integration"}' > journal.json
fm time-off request put /api/v1/journals/2026-08-31 --json-file journal.json
```

Femini uses the documented Bearer Token authentication: obtain the token from
the Profile menu in Femini, then run `fm femini auth login`. Femini does not
document a dedicated identity endpoint, so login/status use a filtered,
read-only clients request as an authentication probe and never print its
response. Femini API tokens have no documented prefix requirement.

Pages uses a personal API key from Pages Console → Connect AI. The key is sent
as a Bearer token and is isolated under `FEEDMOB_PAGES_TOKEN` / the Pages
Keychain entry. The documented Pages lifecycle operations are intentionally
limited to list, detail, stats, publish, update, external sharing, and image
uploads; `delete`, `restore`, `revert`, and `claim` are not exposed by `fm`.

```sh
printf '%s' "$FEEDMOB_PAGES_TOKEN" | fm pages auth login --token-stdin
fm pages list --scope mine --q growth
fm pages publish --owner growth --html-file report.html --visibility unlisted
fm pages asset upload chart.png
```

FeedMob Workspace is the CLI's read-only access to the FeedMob Admin API for
shared operational data. Obtain a personal access token from FeedMob SSO, then
authenticate without placing the token in shell history. The token owner must
have an approved SSO account. A `401 Unauthorized` response can mean that the
token is invalid, expired, or revoked, or that the account is not approved.
Workspace requests are GET-only and must stay under `/api/v1/`. Use
`fm workspace openapi` (or `fm workspace schema`) to fetch the machine-readable
OpenAPI specification for discovery and self-description.

```sh
fm workspace auth login
fm workspace request get /api/v1/me
fm workspace openapi
```

`publish` requires `--owner` and `--html-file`. `update` accepts an HTML
replacement with `--html-file`, small find/replace changes from `--edits-file`,
and optional metadata; the HTML replacement and edits are mutually exclusive.
Advanced `data_sources` and multi-file site payloads are accepted from JSON
files with `--data-sources-file` and `--files-file`.

### JSON output

With `--json` (accepted anywhere on the command line), every command prints
a stable JSON envelope to stdout, including errors:

```json
{"ok":true,"data":{"service":"pixel","authenticated":true}}
```

```json
{"ok":false,"error":{"code":"credential_missing","message":"No Pixel credential is configured."}}
```

## Security notes

- No `--token` flag: credentials never enter shell history or process argv;
- On macOS the Keychain is read and written directly via Security.framework;
  elsewhere an AES-256-GCM encrypted store is used (directory `0700`,
  key/ciphertext/lock files `0600`, atomic writes under a file lock);
- Full tokens never appear in logs, JSON output, or error messages;
- Requests go only to the configured service host over HTTPS; loopback HTTP
  requires an explicit opt-in;
- Generic `request` commands remain GET-only. Pages write operations are
  explicit, field-validated commands rather than a generic write-API escape
  hatch.

## Troubleshooting

- **"Could not read/save … macOS Keychain"**: the login keychain is locked
  (common after a macOS password change). Unlock it with
  `security unlock-keychain login.keychain-db` or via Keychain Access, then
  retry.
- **Gatekeeper blocks a browser-downloaded archive**: the binaries are
  unsigned by design. Installing through Homebrew is the supported path —
  formula downloads carry no quarantine attribute, so Gatekeeper is not
  triggered.
- **`tebako-bootstrap: WARNING … unsigned v1 (legacy) tpkg trailer` on
  stderr**: expected with the current Tebako toolchain; it is informational
  and does not affect JSON stdout or exit codes.
- **First run fails offline or through a proxy**: the runtime image download
  needs github.com access once; set `TEBAKO_RUNTIME_MIRROR` to an internal
  mirror if needed.

## Development and releasing

See [docs/development.md](docs/development.md) for local setup and testing,
and [docs/release.md](docs/release.md) for the Tebako/Homebrew release
pipeline and maintainer workflow.
