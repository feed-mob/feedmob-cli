class Fm < Formula
  desc "Command-line interface for FeedMob services"
  homepage "https://github.com/feed-mob/feedmob-cli"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.2.0/fm-darwin-arm64.tar.gz"
      sha256 "a7bc4818920136065b6b507433015b74aeb7a08ab56295c23267e76289ff0bf7"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.2.0/fm-darwin-x86_64.tar.gz"
      sha256 "1dbe68585d81935074c561dee8924b0acb63f1a4ff454a834b919d59620f8c83"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.2.0/fm-linux-arm64.tar.gz"
      sha256 "e34898ce4faeb03622cb67188dbb99ed93782cd943b61e114367813ea59243df"
    end

    on_intel do
      url "https://github.com/feed-mob/feedmob-cli/releases/download/v0.2.0/fm-linux-x86_64.tar.gz"
      sha256 "b3a65e5e9f0afdb5f99abf74a0e4c4d687761148c0c4a7a45e5a269988d56bc2"
    end
  end

  def install
    bin.install "fm"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/fm --json version")
  end
end
