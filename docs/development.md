# Development

## Setup

Requires Ruby 3.2+ (the repo pins `.ruby-version`; rbenv is used when
available):

```sh
bundle install
```

Run the CLI from the working tree:

```sh
bundle exec exe/fm version
bundle exec exe/fm doctor
```

Install it like an end user (isolated gem home under `~/.local`):

```sh
make install-local
export PATH="$HOME/.local/bin:$PATH"
```

`PREFIX=/your/prefix make install-local` changes the install location.

## Tests and lint

```sh
bundle exec rake test
bundle exec rubocop --format simple
```

Both run in CI on every PR, along with the release-packaging test matrix
(four native targets) and Formula checks. Platform-specific release tests
skip automatically on non-matching hosts.

## Layout

- `lib/feedmob/cli/` — commands, credential storage (Keychain on macOS,
  AES-256-GCM encrypted file elsewhere), HTTP client, JSON envelope
- `exe/fm` — entry point
- `script/` — release pipeline scripts (build, verify, publish, formula)
- `packaging/` — pinned Tebako/Ruby release configuration and runtime Gemfile
- `Formula/fm.rb` — Homebrew formula, rendered at release time

## Releasing

See [release.md](release.md). Versions auto-increment from the latest tag;
publishing is a single manual workflow dispatch with a confirmation gate.
