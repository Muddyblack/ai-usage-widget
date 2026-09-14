{
  description = "AI usage widget for KDE Plasma 6 and Hyprland/Quickshell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = f: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: f system);
      metadata = builtins.fromJSON (builtins.readFile ./package/metadata.json);
    in {
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "ai-usage-widget";
            version = metadata.KPlugin.Version;
            # translate/ comes along so the .mo catalogs (git-ignored) can be compiled.
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [ ./package ./translate ];
            };
            nativeBuildInputs = [ pkgs.gettext ];

            dontConfigure = true;

            buildPhase = ''
              runHook preBuild
              bash translate/build.sh
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              # Install plasmoid package
              root=$out/share/plasma/plasmoids/org.muddyblack.aiUsageWidget
              mkdir -p "$root"
              cp -r package/. "$root/"

              # The shell tools resolve Python from PATH, but plasmashell inherits the
              # systemd user session's PATH, which on NixOS has no Python at all — the
              # widget then renders "python3 missing" for every provider. Pin the
              # interpreter so the installed plasmoid is self-contained; this also puts
              # python3 in the closure so it cannot be garbage-collected away.
              # $PYTHON3 still wins at runtime, the PATH candidates still act as
              # fallbacks, and --replace-fail turns a drifted line into a build error
              # rather than a silently unpatched script.
              substituteInPlace "$root/contents/tools/sh/python-interp.sh" \
                --replace-fail 'PY_DEFAULT="python3"' \
                               'PY_DEFAULT="${pkgs.python3}/bin/python3"'

              # Register icon in hicolor theme so Plasma Widget Explorer picks it up
              mkdir -p "$out/share/icons/hicolor/scalable/apps"
              cp package/contents/icons/org.muddyblack.aiUsageWidget.svg "$out/share/icons/hicolor/scalable/apps/org.muddyblack.aiUsageWidget.svg"

              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Multi-provider AI usage widget for KDE Plasma 6";
              license = licenses.mit;
              platforms = platforms.linux;
              homepage = "https://github.com/Muddyblack/ai-usage-widget";
            };
          };

          tray-helper = pkgs.stdenv.mkDerivation {
            pname = "ai-usage-tray";
            version = metadata.KPlugin.Version;
            src = ./hyprland/tray;
            nativeBuildInputs = with pkgs; [ cmake ninja qt6.wrapQtAppsHook ];
            buildInputs = with pkgs; [ qt6.qtbase ];
          };
        });

      apps = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          quickshellDesktop = pkgs.makeDesktopItem {
            name = "org.quickshell";
            desktopName = "Quickshell";
            comment = "QtQuick desktop shell runtime";
            # xdg-desktop-portal resolves this entry in the portal daemon's
            # environment, where a flake-only Quickshell is not on PATH.
            exec = "${pkgs.quickshell}/bin/qs";
            icon = "org.muddyblack.aiUsageWidget";
            terminal = false;
            noDisplay = true;
            categories = [ "Utility" ];
          };
        in {
          view = {
            type = "app";
            program = toString (pkgs.writeShellScript "view" ''
              if [ ! -f "$PWD/package/metadata.json" ]; then
                echo "error: no plasmoid at $PWD/package" >&2
                echo "  'nix run .#view' previews your working copy, so run it from the repo root." >&2
                exit 1
              fi
              export PATH=${pkgs.lib.makeBinPath [ pkgs.kdePackages.plasma-sdk pkgs.kdePackages.plasma-desktop pkgs.gettext ]}:"$PATH"
              "$PWD/translate/build.sh"
              exec plasmoidviewer \
                -a "$PWD/package" -f "''${1:-planar}"
            '');
          };
          pack = {
            type = "app";
            program = toString (pkgs.writeShellScript "pack" ''
              set -euo pipefail
              here="$PWD"
              ver="$(grep -oE '"Version":[[:space:]]*"[^"]+"' "$here/package/metadata.json" | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
              name="$(basename "$here")"
              out="$here/$name-$ver.plasmoid"
              rm -f "$out"
              PATH=${pkgs.gettext}/bin:"$PATH" "$here/translate/build.sh"
              (cd "$here/package" && ${pkgs.zip}/bin/zip -r "$out" . -x '*.swp' '*~')
              echo "wrote $out"
            '');
          };
          cli = {
            type = "app";
            program = toString (pkgs.writeShellScript "ai-usage-cli" ''
              set -eu
              export PATH=${pkgs.lib.makeBinPath [ pkgs.python3 ]}:"$PATH"
              exec ${self}/package/contents/tools/sh/ai-usage-cli "$@"
            '');
          };
          hyprland = {
            type = "app";
            program = toString (pkgs.writeShellScript "ai-usage-hyprland" ''
              set -eu
              export PATH=${pkgs.lib.makeBinPath [
                pkgs.bash
                pkgs.coreutils
                pkgs.python3
              ]}:"$PATH"
              # The repo root, not hyprland/ — Quickshell roots its QML sandbox at
              # the entry point's directory, and hyprland/ cannot reach the shared
              # JS under package/. See shell.qml.
              config=${self}/shell.qml
              desktop_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/applications"
              ${pkgs.coreutils}/bin/mkdir -p "$desktop_dir"
              ${pkgs.coreutils}/bin/install -m 0644 \
                ${quickshellDesktop}/share/applications/org.quickshell.desktop \
                "$desktop_dir/org.quickshell.desktop"
              ${self.packages.${system}.tray-helper}/bin/ai-usage-tray \
                ${pkgs.quickshell}/bin/qs "$config" \
                ${self}/package/contents/tools/sh/get-ai-usage &
              tray_pid=$!
              trap 'kill "$tray_pid" 2>/dev/null || true' EXIT INT TERM
              ${pkgs.quickshell}/bin/qs -p "$config"
            '');
          };
        });

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            name = "ai-usage-widget-dev";
            packages = with pkgs; [
              qt6.qtdeclarative
              kdePackages.kpackage
              kdePackages.plasma-sdk
              gettext
              pre-commit
              zip
              python3
              ruff
              jq
              nodejs
            ];
            shellHook = ''
              pre-commit install -f --install-hooks
              echo "ai-usage-widget dev shell ready"
              echo "  make help        — list targets (view, install, pack, tag)"
            '';
          };

          # The Windows tray app (windows/) runs on Linux too, which is how it is
          # developed: `nix develop .#windows`, then `python windows/app.py`.
          # Separate because only people working on that app want PySide6.
          windows = pkgs.mkShell {
            name = "ai-usage-widget-windows";
            packages = [
              (pkgs.python3.withPackages (ps: [ ps.pyside6 ps.psutil ]))
              pkgs.ruff
            ];
          };
        });
    };
}
