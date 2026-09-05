class Fm < Formula
  desc "Command-line interface for FeedMob services"
  homepage "https://github.com/feed-mob/feedmob-cli"
  license "MIT"
  version_scheme 1

  on_macos do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.2/fm-darwin-arm64.tar.gz"
      sha256 "ecb1f910bb7d10ea683712b7dc5ef3cd1edd6461976b391d635144fa6d68d37e"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.2/fm-darwin-x86_64.tar.gz"
      sha256 "969d53bc46bbd16839ce6f96ff4bcab8ef99b93d93faf92422456472d48e4036"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.2/fm-linux-arm64.tar.gz"
      sha256 "915d2f811fe18d4d7b45c5b83da4b05e790fe04a6cdb35d9789fe282c8c6e771"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.2/fm-linux-x86_64.tar.gz"
      sha256 "756d1c460199c5a7c85a5a8867f6de1c7fbd5c425c67c5dd36c2099ad63d0652"
    end
  end

  def install
    bin.install "fm"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/fm --json version")
  end
end
