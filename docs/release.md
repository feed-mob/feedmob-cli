# Release pipeline (maintainers)

Releases are built with Tebako and distributed through Homebrew. The Homebrew
formula lives in this repository at `Formula/fm.rb` — no separate tap repo and
no extra credentials are involved.

## Artifacts and targets

Four native targets, each built and verified on a matching GitHub-hosted
runner (no Rosetta/QEMU for real artifacts):

| Target | Runner | Archive |
| --- | --- | --- |
| `macos-arm64` | `macos-15` | `fm-darwin-arm64.tar.gz` |
| `macos-x86_64` | `macos-15-intel` | `fm-darwin-x86_64.tar.gz` |
| `linux-arm64` | `ubuntu-24.04-arm` | `fm-linux-arm64.tar.gz` |
| `linux-x86_64` | `ubuntu-24.04` | `fm-linux-x86_64.tar.gz` |

Each archive contains a single `fm` executable. Linux support requires
GNU/glibc >= 2.35 (Ubuntu 22.04-compatible); Alpine/musl is not supported.

macOS binaries are intentionally unsigned and not notarized: formula downloads
via `brew install` carry no quarantine attribute, so Gatekeeper is not
triggered. Downloading the archive in a browser and installing by hand is not
a supported path.

## Pinned toolchain

`packaging/release.yml` pins the Tebako tool version + per-target SHA-256, the
Tebako runtime format version, and the full Ruby patch version.
`packaging/Gemfile` contains runtime dependencies only — never run
`tebako press` against the repository root.

Tebako 0.16.x is the image-era runtime: the interpreter is embedded in the
package, but the ~11 MB runtime image (`.tfs`) is downloaded once on first
run from the official tamatebako release, SHA-256 verified, and cached
machine-wide in `~/.tebako/runtimes/`. End users therefore need github.com
access on first run; `TEBAKO_RUNTIME_MIRROR` (https or file://) can point at
an internal mirror.

## Local scripts

```sh
script/fetch-tebako-tool --target linux-x86_64 --output /tmp/tebako
script/press-release-artifact --target linux-x86_64 --tebako /tmp/tebako --output /tmp/fm
script/package-homebrew-artifact --target linux-x86_64 --artifact /tmp/fm --tebako /tmp/tebako --output /tmp/release-linux-x86_64
```

Verification covers the Mach-O/ELF architecture, the Linux glibc requirement,
`tebako inspect` runtime provenance (the runtime_ref must match the pinned
Ruby/Tebako versions), and a version smoke in an environment without
Ruby/Gem. Flatten the four per-target output directories into one input
directory, then:

```sh
script/assemble-homebrew-release --input /tmp/release-input --output /tmp/feedmob-cli-release
script/render-homebrew-formula --version 0.1.0 \
  --assets-json /tmp/feedmob-cli-release/release-assets.json \
  --output Formula/fm.rb
```

## Workflow

`.github/workflows/release.yml` is manual (`workflow_dispatch`). There is no
version input: the next version is computed from the latest release tag plus
the `bump` input (`patch`/`minor`/`major`, default `patch`).

- `publish=false` (default) is a dry run: build, verify, keep workflow
  artifacts. Linux builds additionally run `script/smoke-release-auth`, an
  end-to-end encrypted-file credential login/status/logout check against a
  loopback fake API with a sentinel token.
- `publish=true` performs the release. The validate job enforces
  default-branch ancestry, that the computed version was not released before,
  and that the `confirm` input is exactly `release`; the write jobs declare
  `environment: release` (deployment restricted to `main`).

Publish sequence:

1. The `bump` job commits the `version.rb` bump to `main` as the release bot
   and every later job builds from that commit, so `fm version` reports the
   released version. A failed run leaves no tag behind, so re-running computes
   the same version again.
2. The `publish` job runs `script/publish-release`: create a draft Release at
   the bump commit, auto-generate "What's Changed" notes from merged PRs since
   the previous tag (checksums appended), upload the four archives plus
   `SHA256SUMS`, read every asset back via the API (name/size/digest), then
   undraft. Any failure leaves a draft; a published release is never
   overwritten.
3. The `formula-pr` job renders `Formula/fm.rb` from the assembled manifest,
   runs `brew style` and `brew audit --online`, and opens a
   `release/fm-<version>` PR in this repo. A human reviews and merges it —
   the workflow never merges Formula PRs.

Everything uses the workflow's own `GITHUB_TOKEN`; the only configuration
needed is the `release` environment restricted to the `main` branch.

To publish:

```sh
gh workflow run release.yml --ref main -f bump=patch -f publish=true -f confirm=release
```

## Rollback

There are no versioned formulas: each release overwrites `Formula/fm.rb`.
To roll back a bad Formula, revert the corresponding `release/fm-*` PR —
earlier states are always recoverable from git history, and users can
`brew pin fm` to hold their installed version. Published releases and tags
are never overwritten or deleted; fixes ship as a new version.
