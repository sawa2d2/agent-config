{
  description = "Standalone Nix packages for agent-config";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
      };
    in {
      packages.${system} = {
        codecompanion-nvim = pkgs.vimPlugins.codecompanion-nvim;
        plenary-nvim = pkgs.vimPlugins.plenary-nvim;
      };
    };
}
