{
  description = "Gas Town rig configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    gastown-nix = {
      url = "github:keithschulze/gastown.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      gastown-nix,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        gcLib = gastown-nix.lib;

        pack = gcLib.mkPack {
          inherit pkgs;
          config = {
            name = "my-project";
            agents.mayor.promptTemplate = ./agents/mayor/prompt.template.md;
            namedSessions = [
              { template = "mayor"; mode = "always"; scope = "city"; }
            ];
          };
        };

        city = gcLib.mkCity {
          inherit pkgs pack;
          config = {
            workspace.provider = "claude";
            rigs = [ "my-project" ];
          };
        };
      in
      {
        # `nix build .#pack` — pack tree (pack.toml + agents/)
        # `nix build .#city` — pack tree merged with city.toml
        packages = {
          inherit pack;
          city = city.tree;
          default = city.tree;
        };
      }
    );
}
