class Fm < Formula
  desc "Command-line interface for FeedMob services"
  homepage "https://github.com/feed-mob/feedmob-cli"
  license "MIT"
  version_scheme 1

  on_macos do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.3.1/fm-darwin-arm64.tar.gz"
      sha256 "bed7706d1e80895d9902313891ea874d175a1822111d833eee8fce799209abc1"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.3.1/fm-darwin-x86_64.tar.gz"
      sha256 "52107adc81d7df7de17299a482d0ca53ec8b4d832e6a77676f6747a8524e8141"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.3.1/fm-linux-arm64.tar.gz"
      sha256 "ecdcc8afa7fe56289cb57f92d67707ff1bbf90a9d3af4ef984228c15d6a478bd"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.3.1/fm-linux-x86_64.tar.gz"
      sha256 "cd710b365f94be59fb7b8f80d5dc5a5436951acb0f7afabc93c177090e5ec155"
    end
  end

  def install
    bin.install "fm"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/fm --json version")
  end
end
