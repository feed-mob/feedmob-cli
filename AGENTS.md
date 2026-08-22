# AGENTS.md

Guidance for AI coding agents working in this repository.

## What this is

`fm` is the FeedMob CLI: a Ruby gem packaged into native binaries with
Tebako and distributed via Homebrew (the formula lives in `Formula/fm.rb` in
this repo). See `README.md` for user-facing behavior.

## Setup and verification

```sh
bundle install
bundle exec exe/fm version     # run from the working tree
bundle exec rake test          # minitest
bundle exec rubocop --format simple
```

Tests and RuboCop must pass before opening a PR; CI also runs the
release-packaging test matrix and Formula checks. Target Ruby is 3.2+
(`.ruby-version` pins the exact patch).

## Conventions

- `# frozen_string_literal: true` in every Ruby file; follow existing style,
  RuboCop config is the authority.
- Runtime dependencies go in the gemspec and `packaging/Gemfile` only — the
  release build packages just those. Dev/test dependencies stay in the root
  `Gemfile`.
- `Formula/fm.rb` is rendered by `script/render-homebrew-formula` during a
  release. Never hand-edit it outside the release flow; it follows brew
  style and is excluded from project RuboCop.
- `FeedMob::CLI::VERSION` is bumped by the release workflow, not by hand.
  Tests must derive expected versions from the constant, never hardcode one.

## Security rules (hard requirements)

- Credentials never appear in argv, logs, JSON output, error messages, or
  test fixtures. Tests use sentinel tokens and loopback HTTP servers only.
- Never touch the real macOS Keychain in tests — inject the fakes provided
  through the `Keychain` constructor.
- Base URLs are HTTPS-only; plain HTTP is allowed solely for loopback with
  explicit `FEEDMOB_ALLOW_INSECURE_HTTP=1`.
- Never overwrite a published tag or GitHub Release; the release pipeline
  refuses to and so should you.

## Releasing

See `docs/release.md`. Releases are a manual workflow dispatch with
auto-incremented versions; Formula PRs are always reviewed by a human.
