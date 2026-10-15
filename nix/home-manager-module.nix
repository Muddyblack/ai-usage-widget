self:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.ai-usage-widget;
  system = pkgs.stdenv.hostPlatform.system;
  pluginId = "org.muddyblack.aiUsageWidget";
in
{
  options.programs.ai-usage-widget = {
    enable = lib.mkEnableOption "the AI usage widget, provider limits for KDE Plasma 6, Hyprland/Quickshell and the terminal";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${system}.default;
      defaultText = lib.literalExpression "inputs.ai-usage.packages.\${system}.default";
      description = "The Plasma widget package.";
    };

    plasmoid.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Link the Plasma widget into ~/.local/share/plasma/plasmoids, so Widget Explorer
        finds it and a new build replaces the old one on the next login. Turn off on a
        desktop without Plasma.
      '';
    };

    cli = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install `ai-usage-cli` and `get-ai-usage`: the terminal frontend, for SSH, prompts and status bars. No Qt involved.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${system}.cli;
        defaultText = lib.literalExpression "inputs.ai-usage.packages.\${system}.cli";
        description = "The command line package.";
      };
    };

    desktop = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install the tray app with the floating pill, for any desktop with a tray (GNOME, Sway, XFCE, ...). No Plasma or Quickshell needed.";
      };
      autostart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Start the tray app when you log in.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${system}.desktop;
        defaultText = lib.literalExpression "inputs.ai-usage.packages.\${system}.desktop";
        description = "The tray app package.";
      };
    };

    hyprland = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install the Quickshell panel and its tray helper for Hyprland. Start it with `ai-usage-hyprland`, e.g. from exec-once.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${system}.hyprland;
        defaultText = lib.literalExpression "inputs.ai-usage.packages.\${system}.hyprland";
        description = "The Hyprland/Quickshell package.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = lib.optional cfg.plasmoid.enable cfg.package
      ++ lib.optional cfg.cli.enable cfg.cli.package
      ++ lib.optional cfg.desktop.enable cfg.desktop.package
      ++ lib.optional cfg.hyprland.enable cfg.hyprland.package;

    xdg.configFile."autostart/ai-usage.desktop" = lib.mkIf (cfg.desktop.enable && cfg.desktop.autostart) {
      text = ''
        [Desktop Entry]
        Type=Application
        Name=AI Usage
        Exec=${cfg.desktop.package}/bin/ai-usage
        Icon=org.muddyblack.aiUsageWidget
        X-GNOME-Autostart-enabled=true
      '';
    };

    xdg.dataFile = lib.mkIf cfg.plasmoid.enable {
      "plasma/plasmoids/${pluginId}" = {
        source = "${cfg.package}/share/plasma/plasmoids/${pluginId}";
        force = true;
      };
    };
  };
}
