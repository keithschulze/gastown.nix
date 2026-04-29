{
  description = "Gas Town rig configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    gastown-nix = {
      url = "github:keithschulze/gastown.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      gastown-nix,
    }:
    let
      lib = nixpkgs.lib;

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      forAllSystems =
        f:
        lib.genAttrs systems (
          system:
          f {
            pkgs = import nixpkgs { inherit system; };
            inherit system;
          }
        );
    in
    {
      apps = forAllSystems (
        { pkgs, system }:
        let
          rig = gastown-nix.lib.mkRig {
            inherit pkgs;
            gtPackage = gastown-nix.packages.${system}.gt;
            bdPackage = gastown-nix.packages.${system}.bd;
            config = {
              name = "my-project";
              gitUrl = "git@github.com:org/project.git";
              beads.prefix = "mp";
              crew.alice = {
                role = "developer";
              };
            };
          };
        in
        {
          mayorAttach = {
            type = "app";
            program = "${rig.mayorAttach}/bin/gt-mayor-attach";
          };
        }
      );

      devShells = forAllSystems (
        { pkgs, system }:
        {
          default = pkgs.mkShell {
            buildInputs = [
              gastown-nix.packages.${system}.gt
              gastown-nix.packages.${system}.bd
            ];
          };
        }
      );
    };
}
