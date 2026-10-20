cask "tidesi" do
  arch arm: "apple-silicon", intel: "intel"

  version "4.0.0"
  sha256 arm:   "dd1ff0d37e4605c97d97cef48395a082895f95abd6192b515d6d9440969fe10a",
         intel: "11b934c84b7b9d1059cbe3581dba71511d0e3c067efe2592763a06e231473385"

  url "https://github.com/Muddyblack/tidesi/releases/download/v#{version}/tidesi-macos-#{version}-#{arch}.dmg"
  name "Tidesi"
  desc "Menu bar monitor for AI provider usage limits"
  homepage "https://github.com/Muddyblack/tidesi"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "Tidesi.app"

  zap trash: [
    "~/.cache/tidesi",
    "~/.config/tidesi",
    "~/.local/share/tidesi",
  ]

  caveats <<~EOS
    Tidesi is not notarized yet. If macOS blocks the first launch, choose
    Open Anyway in System Settings > Privacy & Security.
  EOS
end
