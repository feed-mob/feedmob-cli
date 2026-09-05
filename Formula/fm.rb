class Fm < Formula
  desc "Command-line interface for FeedMob services"
  homepage "https://github.com/feed-mob/feedmob-cli"
  license "MIT"
  version_scheme 1

  on_macos do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.3/fm-darwin-arm64.tar.gz"
      sha256 "7ef3051229ebaae915f017d1a53f30f86bc73de72623138448940e1a9ff4c34f"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.3/fm-darwin-x86_64.tar.gz"
      sha256 "1f121a09feed00c9be004edaaaea16776312d49ef4e45bed1f29df0d93f88d26"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.3/fm-linux-arm64.tar.gz"
      sha256 "7b6d028eeb70fcc91be9cf69bb5f0ac39b8946916de8a28bd030e4b41e614046"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.3/fm-linux-x86_64.tar.gz"
      sha256 "fc4c73a4c90777043b77f88ecb8a8acaeae39de3147122860d2435d9e27a125c"
    end
  end

  def install
    bin.install "fm"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/fm --json version")
  end
end
