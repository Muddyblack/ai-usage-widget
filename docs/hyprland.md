# Hyprland / Caelestia

Run the Quickshell widget together with its standard StatusNotifier tray icon:

```bash
# From a cloned checkout
nix run .#hyprland

# Or run the current GitHub version directly
nix run github:Muddyblack/kde-ai-usage#hyprland
```

During development, use `nix run path:.#hyprland` if newly created files have
not been added to Git yet; regular users do not need the `path:` form.

The tray icon works with any panel that hosts freedesktop StatusNotifier items,
including Caelestia and Waybar. The **Pill** setting offers **Always**, **Edge
hover**, and **Tray only** modes. Edge-hover mode keeps only a small screen-edge
hotspot and reveals the usage pill without polling. Six top/bottom position
presets place both the pill and popup consistently. Clicking the tray icon
toggles the popup; clicking outside the popup closes it.

The Hyprland frontend supports the same provider set as the Plasma widget,
including Z.AI, GitHub Copilot, and DeepSeek. Enable these newer providers and
enter their credentials in the popup settings page; they default to off. The
settings are stored locally in
`~/.config/ai-usage-widget/hyprland-settings.json` (or under
`$XDG_CONFIG_HOME`).

*Settings → Panel → Language* picks the panel's language and switches it on the
spot. By default it follows `$LANGUAGE`, or else the locale's language, when
`translate/` has a catalog for it (French so far), reading the same `.po` files
as the Plasma widget. Provider rows the backend words itself (limits, token counts) and the
menu of the separate tray helper (`hyprland/tray`) are still English.
