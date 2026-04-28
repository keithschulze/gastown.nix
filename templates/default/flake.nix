{
  description = "Gas Town project configuration";

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
    let
      townConfig = {
        settings.defaultAgent = "claude";

        rigs.my-project = {
          gitUrl = "git@github.com:org/project.git";
          defaultBranch = "main";
          beads.prefix = "mp";
          maxPolecats = 5;
          crew.alice = {
            role = "developer";
          };
        };
      };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        town = gastown-nix.lib.mkTown {
          inherit pkgs;
          config = townConfig;
        };
      in
      {
        packages.default = town.activate;

        apps.default = {
          type = "app";
          program = "${town.activate}/bin/gt-activate";
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            gastown-nix.packages.${system}.gt
            gastown-nix.packages.${system}.bd
          ];
        };
      }
    );
}
