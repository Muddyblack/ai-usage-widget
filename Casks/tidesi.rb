cask "tidesi" do
  arch arm: "apple-silicon", intel: "intel"

  version "4.0.1"
  sha256 arm:   "0a1411d5b36fc1f4f232548e68e0e0b74addc08743e8254d82df22f1cc8c29ae",
         intel: "1a26b5d660d8bef214a78c16eb49e993344accb47ab1a6ab86fad2dd66bd6357"

  url "https://github.com/Muddyblack/tidesi/releases/download/v#{version}/tidesi-macos-#{version}-#{arch}.dmg"
  name "tideSI"
  desc "Menu bar monitor for AI provider usage limits"
  homepage "https://github.com/Muddyblack/tidesi"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "tideSI.app"

  zap trash: [
    "~/.cache/tidesi",
    "~/.config/tidesi",
    "~/.local/share/tidesi",
  ]

  caveats <<~EOS
    tideSI is not notarized yet. If macOS blocks the first launch, choose
    Open Anyway in System Settings > Privacy & Security.
  EOS
end
