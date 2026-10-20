# The nixpkgs-style packages, laid out like pkgs/by-name in nixpkgs. They fetch
# a tagged release from GitHub instead of building the working tree.
#
#   nix-build nix/nixpkgs -A tidesi
#   nix-update --file nix/nixpkgs tidesi --version 3.3.1   # bump version and hash
#
# The release workflow does the second step for you (see docs/packaging.md).
{
  pkgs ? import <nixpkgs> { },
}:
{
  tidesi = pkgs.callPackage ./tidesi/package.nix { };
  tidesi-app = pkgs.callPackage ./tidesi-app/package.nix { };
  tidesi-cli = pkgs.callPackage ./tidesi-cli/package.nix { };
}
