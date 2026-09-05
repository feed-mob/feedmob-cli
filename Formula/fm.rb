class Fm < Formula
  desc "Command-line interface for FeedMob services"
  homepage "https://github.com/feed-mob/feedmob-cli"
  license "MIT"
  version_scheme 1

  on_macos do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.1/fm-darwin-arm64.tar.gz"
      sha256 "153b0b5ba934de06aa115284a051679a158f1cb5ba09e4b29fa42749439e1ded"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.1/fm-darwin-x86_64.tar.gz"
      sha256 "b1c992425044bc614b8aace24aa5f337be5fd821d3436637cd80f463ea0f7424"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.1/fm-linux-arm64.tar.gz"
      sha256 "447536610529c3baf9c2465da412951259abb3494a74b723b286d990c33e8ec0"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.1/fm-linux-x86_64.tar.gz"
      sha256 "bf43886ced18664ca3ab74bb33a5648bb3b1cf8fb5c0dbd6022fc64b124cd67a"
    end
  end

  def install
    bin.install "fm"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/fm --json version")
  end
end
