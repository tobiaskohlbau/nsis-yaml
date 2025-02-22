{
  description = "nsis-yaml";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      flake-utils,
      ...
    }@inputs:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            inputs.zig.overlays.default
            (final: prev: {
              unstable = nixpkgs-unstable.legacyPackages."${system}";
            })
          ];
        };
      in
      {
        devShells.default = import ./shell.nix { inherit pkgs; };
        formatter = pkgs.nixfmt-rfc-style;
      }
    );
}
