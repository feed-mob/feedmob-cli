class Fm < Formula
  desc "Command-line interface for FeedMob services"
  homepage "https://github.com/feed-mob/feedmob-cli"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.1.1/fm-darwin-arm64.tar.gz"
      sha256 "7a47267351599cd90733567e8282d6e61551b7b14d493deb29edae7468867afe"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.1.1/fm-darwin-x86_64.tar.gz"
      sha256 "8e4f2530753b1d6947acb10fcd1e46f405951b146b5747b435c0f5785cc8bb86"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.1.1/fm-linux-arm64.tar.gz"
      sha256 "2ede0ecd83d09d53615650d0630761acb58a8a4259bfca972ee2e1fe8f3b8b35"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.1.1/fm-linux-x86_64.tar.gz"
      sha256 "93e9777fe0531f7816eeba62c7f839e1eeed45dec3c7eff82e6bbe6926bcf60d"
    end
  end

  def install
    bin.install "fm"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/fm --json version")
  end
end
