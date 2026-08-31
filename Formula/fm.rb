class Fm < Formula
  desc "Command-line interface for FeedMob services"
  homepage "https://github.com/feed-mob/feedmob-cli"
  license "MIT"
  version_scheme 1

  on_macos do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.0/fm-darwin-arm64.tar.gz"
      sha256 "d10fc24448dbfd60841686073f6ddf25e56ba01aa6395313f6a84e4fbdd23c6f"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.0/fm-darwin-x86_64.tar.gz"
      sha256 "03217b4c7c37497b735ed490d4438d4c5cb8c0eac65f49587bb1ee3c0b458933"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.0/fm-linux-arm64.tar.gz"
      sha256 "6c52bab8c23b63593d535469dbc32cd7e34edbc010c3c67c39a1449aef9835f1"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.0/fm-linux-x86_64.tar.gz"
      sha256 "eddf9ddd8f54963f80692de7892e7877677ca94c885de5586cf4ba69d08c5295"
    end
  end

  def install
    bin.install "fm"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/fm --json version")
  end
end
