# The nixpkgs-style packages, laid out like pkgs/by-name in nixpkgs. They fetch
# a tagged release from GitHub instead of building the working tree.
#
#   nix-build nix/nixpkgs -A ai-usage-widget
#   nix-update --file nix/nixpkgs ai-usage-widget --version 3.3.1   # bump version and hash
#
# The release workflow does the second step for you (see docs/packaging.md).
{
  pkgs ? import <nixpkgs> { },
}:
{
  ai-usage-widget = pkgs.callPackage ./ai-usage-widget/package.nix { };
  ai-usage-app = pkgs.callPackage ./ai-usage-app/package.nix { };
  ai-usage-cli = pkgs.callPackage ./ai-usage-cli/package.nix { };
}
