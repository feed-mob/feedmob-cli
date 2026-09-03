class Fm < Formula
  desc "Command-line interface for FeedMob services"
  homepage "https://github.com/feed-mob/feedmob-cli"
  license "MIT"
  version_scheme 1

  on_macos do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.0/fm-darwin-arm64.tar.gz"
      sha256 "8eecfac7782a0579753a4701ca4982b86d59a382c498b0219f8944bcc3c923f8"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.0/fm-darwin-x86_64.tar.gz"
      sha256 "cfd2bdaea3168ddf869f56346de15af091cd0870ea0427f1a474c114a957251e"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.0/fm-linux-arm64.tar.gz"
      sha256 "7c4fcbed2644bf1a0f20bdeb67f1063f15f5746759281884b29b273953c6fe98"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.4.0/fm-linux-x86_64.tar.gz"
      sha256 "03a077843d5caffe9f847dc6fc2f00a2a24baa1ece7841f283a32488e82e1b43"
    end
  end

  def install
    bin.install "fm"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/fm --json version")
  end
end
