"""Write the Homebrew cask (Casks/tidesi.rb) for one stable release.

The repository doubles as a Homebrew tap, as it does as a Scoop bucket. The
hashes are those GitHub reports for the release's DMGs, so nothing is
downloaded. Run by .github/workflows/homebrew-tap.yml; no third-party modules.
"""

import argparse
import re
from pathlib import Path

HOMEPAGE = "https://github.com/Muddyblack/tidesi"
SHA256 = re.compile(r"[0-9a-f]{64}")


def cask(version, arm_sha, intel_sha):
    version = version.removeprefix("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Expected a stable version such as 4.0.0 or v4.0.0")
    for sha in (arm_sha, intel_sha):
        if not SHA256.fullmatch(sha):
            raise ValueError(f"Not a SHA-256: {sha!r}")
    return f"""cask "tidesi" do
  arch arm: "apple-silicon", intel: "intel"

  version "{version}"
  sha256 arm:   "{arm_sha}",
         intel: "{intel_sha}"

  url "{HOMEPAGE}/releases/download/v#{{version}}/tidesi-macos-#{{version}}-#{{arch}}.dmg"
  name "TideSI"
  desc "Menu bar monitor for AI provider usage limits"
  homepage "{HOMEPAGE}"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "TideSI.app"

  zap trash: [
    "~/.cache/tidesi",
    "~/.config/tidesi",
    "~/.local/share/tidesi",
  ]

  caveats <<~EOS
    TideSI is not notarized yet. If macOS blocks the first launch, choose
    Open Anyway in System Settings > Privacy & Security.
  EOS
end
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--arm-sha256", required=True)
    parser.add_argument("--intel-sha256", required=True)
    parser.add_argument("--output", type=Path, default=Path("Casks/tidesi.rb"))
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(cask(args.version, args.arm_sha256, args.intel_sha256), encoding="utf-8")


if __name__ == "__main__":
    main()
