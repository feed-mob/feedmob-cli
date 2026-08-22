# FeedMob CLI (`fm`)

`fm` is the command-line interface for FeedMob services. It manages isolated
credentials for Pixel and Time Off, verifies identity, and issues read-only
API requests — with stable JSON output designed for scripts and automation.

```text
fm doctor
fm version
fm pixel auth login [--token-stdin]
fm pixel auth status
fm pixel auth logout
fm pixel request get <path>
fm time-off auth login [--token-stdin]
fm time-off auth status
fm time-off auth logout
fm time-off request get <path>
```

## Installation

### Homebrew (macOS and Linux)

```sh
brew tap feed-mob/tap https://github.com/feed-mob/feedmob-cli.git
brew install feed-mob/tap/fm
```

Prebuilt binaries ship for macOS arm64/x86_64 and Linux arm64/x86_64
(GNU/glibc >= 2.35, i.e. Ubuntu 22.04 or newer; Alpine/musl is not
supported). No Ruby installation is required. On first run the binary
downloads its ~11 MB runtime image once (SHA-256 verified, cached in
`~/.tebako/runtimes/`), so the first invocation needs access to github.com.

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

## Configuration

Each service keeps its own credential, resolved in this order:

1. The service's environment variable;
2. The macOS Keychain, or an AES-256-GCM encrypted local store elsewhere;
3. Unconfigured.

| Service | Token env var | Default endpoint | Identity endpoint | Logout behavior |
| --- | --- | --- | --- | --- |
| Pixel | `FEEDMOB_PIXEL_TOKEN` | `https://feedmob-pixel-dashboard.feedmob.com/rails` | `GET /api/v1/cli/me` | Revokes remotely, deletes local store |
| Time Off | `FEEDMOB_TIME_OFF_TOKEN` | `https://time-off.feedmob.com` | `GET /api/v1/me` | Deletes local store only |

```sh
# Interactive, hidden input; the token never appears in argv or history
fm pixel auth login
fm pixel auth status

# Explicitly read from stdin, for automation
printf '%s' "$FEEDMOB_PIXEL_TOKEN" | fm pixel auth login --token-stdin
```

Endpoints can be overridden with `FEEDMOB_PIXEL_BASE_URL` and
`FEEDMOB_TIME_OFF_BASE_URL`. Overrides must use HTTPS; plain HTTP is only
accepted for loopback addresses (`localhost`, `127.0.0.1`, `::1`) together
with an explicit `FEEDMOB_ALLOW_INSECURE_HTTP=1` — never set that variable
in shared or production environments.

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
- Only GET requests are exposed — no write-API escape hatch.

## Development and releasing

See [docs/development.md](docs/development.md) for local setup and testing,
and [docs/release.md](docs/release.md) for the Tebako/Homebrew release
pipeline and maintainer workflow.
