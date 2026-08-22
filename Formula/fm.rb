class Fm < Formula
  desc "Command-line interface for FeedMob services"
  homepage "https://github.com/feed-mob/feedmob-cli"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.1.0/fm-darwin-arm64.tar.gz"
      sha256 "90f24826ba502ff00ae3d294c73896140deb5f27cc609826a95ded89e66ba952"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.1.0/fm-darwin-x86_64.tar.gz"
      sha256 "09e6008c518ddaba515b8108697125b82a562ab8efa59b48a61de5d27e2ac201"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.1.0/fm-linux-arm64.tar.gz"
      sha256 "48bddf4fd850c059d43199e9f8d41fbe3fbd91d4782c7eddeff7cafb9a108535"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.1.0/fm-linux-x86_64.tar.gz"
      sha256 "7838ad786c1d4841199dc395c008a0e0de78768038fc65e29169a82d581d0853"
    end
  end

  def install
    bin.install "fm"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/fm --json version")
  end
end
