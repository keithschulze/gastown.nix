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

        rig = gastown-nix.lib.mkRig {
          inherit pkgs;
          gcPackage = gastown-nix.packages.${system}.gc;
          config = {
            name = "my-project";
            gitUrl = "git@github.com:org/project.git";
            beads.prefix = "mp";
            # doltPort = 3308;  # Change when running multiple GT instances on the same machine
            crew.alice = {
              role = "developer";
            };
          };
        };
      in
      {
        apps.mayorAttach = {
          type = "app";
          program = "${rig.mayorAttach}/bin/gt-mayor-attach";
        };

        apps.test = {
          type = "app";
          program = "${rig.test}/bin/gt-test-rig";
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            gastown-nix.packages.${system}.gc
            pkgs.dolt
          ];
        };
      }
    );
}
