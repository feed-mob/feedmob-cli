class Fm < Formula
  desc "Command-line interface for FeedMob services"
  homepage "https://github.com/feed-mob/feedmob-cli"
  license "MIT"
  version_scheme 1

  on_macos do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.3.2/fm-darwin-arm64.tar.gz"
      sha256 "1a84840179cf24bbb3f31301ea713a008c340032abcb7897e741ff1e0a305388"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.3.2/fm-darwin-x86_64.tar.gz"
      sha256 "1da990d78bf1aa0975194d8aeba932a6f92e3cf9b6844207314484999e5ea8c2"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.3.2/fm-linux-arm64.tar.gz"
      sha256 "1d9b056c31260fa6e7c331725178725e9c260c6ac2b42ee4f1828b0b5bdd177c"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.3.2/fm-linux-x86_64.tar.gz"
      sha256 "a5c4c6be1097eab356129a724e288b5339cad2649bdfcc61039c396c72e4a1a3"
    end
  end

  def install
    bin.install "fm"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/fm --json version")
  end
end
