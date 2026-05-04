{
  description = "Nix packaging and declarative rig configuration for Gas Town";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    gascity-src = {
      url = "github:gastownhall/gascity";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      gascity-src,
    }:
    let
      lib = nixpkgs.lib;
      gastownLib = import ./lib { inherit lib; };

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
      lib = gastownLib;

      packages = forAllSystems (
        { pkgs, system }:
        let
          gc = pkgs.buildGoModule {
            pname = "gascity";
            version = "1.0.0";
            src = gascity-src;

            subPackages = [ "cmd/gc" ];
            tags = [ "gms_pure_go" ];
            doCheck = false;

            proxyVendor = true;
            vendorHash = "sha256-59k7xFBaLZJ50KWNhwIzttE8j7GXZPneq6o4eUTlvBI=";

            postPatch = ''
              goVer="$(go env GOVERSION | sed 's/^go//')"
              go mod edit -go="$goVer"
            '';

            env.GOTOOLCHAIN = "auto";

            nativeBuildInputs = [ pkgs.git ];

            meta = with pkgs.lib; {
              description = "Gas City (gc) - unified CLI for Gas Town and Beads";
              homepage = "https://github.com/gastownhall/gascity";
              license = licenses.mit;
              mainProgram = "gc";
            };
          };
        in
        {
          inherit gc;
          default = gc;
        }
      );

      apps = forAllSystems (
        { pkgs, system }:
        let
          packToml = gastownLib.mkPack {
            inherit pkgs;
            config = {
              name = "gt_nix";
              agents = {
                mayor = {
                  scope = "town";
                  maxConcurrent = 1;
                };
                witness = {
                  scope = "rig";
                  maxConcurrent = 1;
                };
                polecat = {
                  scope = "rig";
                  maxConcurrent = 10;
                };
              };
            };
          };
          city = gastownLib.mkCity {
            inherit pkgs packToml;
            gcPackage = self.packages.${system}.gc;
            config = {
              workspace.name = "gt_nix";
              rigs.gt_nix = {
                path = ".";
                gitUrl = "git@github.com:keithschulze/gastown.nix.git";
              };
            };
          };
        in
        {
          gc = {
            type = "app";
            program = "${self.packages.${system}.gc}/bin/gc";
          };
          gcUp = {
            type = "app";
            program = "${city.gcUp}/bin/gc-up";
          };
          gcDown = {
            type = "app";
            program = "${city.gcDown}/bin/gc-down";
          };
          gcAttach = {
            type = "app";
            program = "${city.gcAttach}/bin/gc-attach";
          };
          default = self.apps.${system}.gc;
        }
      );

      devShells = forAllSystems (
        { pkgs, system }:
        {
          default = pkgs.mkShell {
            buildInputs = [
              self.packages.${system}.gc
            ];
          };
        }
      );

      checks = forAllSystems (
        { pkgs, system }:
        let
          pythonWithTomli = pkgs.python3.withPackages (ps: [ ps.tomli ]);
        in
        {
          check-pack-toml =
            let
              packToml = gastownLib.mkPack {
                inherit pkgs;
                config = {
                  name = "test-pack";
                  agents = {
                    mayor = {
                      scope = "town";
                      maxConcurrent = 1;
                    };
                    witness = {
                      scope = "rig";
                      maxConcurrent = 1;
                    };
                    polecat = {
                      scope = "rig";
                      maxConcurrent = 10;
                    };
                  };
                };
              };
            in
            pkgs.runCommand "check-pack-toml" { nativeBuildInputs = [ pythonWithTomli ]; } ''
              python3 -c "
              import tomli, sys
              with open('${packToml}', 'rb') as f:
                  data = tomli.load(f)

              # Validate pack metadata
              assert data['pack']['name'] == 'test-pack', f'name: {data[\"pack\"][\"name\"]}'
              assert data['pack']['schema'] == 1, f'schema: {data[\"pack\"][\"schema\"]}'

              # Validate agents
              assert 'mayor' in data['agents'], 'missing mayor'
              assert data['agents']['mayor']['scope'] == 'town'
              assert data['agents']['mayor']['max_concurrent'] == 1
              assert data['agents']['witness']['scope'] == 'rig'
              assert data['agents']['polecat']['scope'] == 'rig'
              assert data['agents']['polecat']['max_concurrent'] == 10

              print('pack.toml validation passed')
              "
              touch $out
            '';

          check-city-toml =
            let
              packToml = gastownLib.mkPack {
                inherit pkgs;
                config = {
                  name = "city-test";
                  agents.mayor = {
                    scope = "town";
                    maxConcurrent = 1;
                  };
                };
              };
              city = gastownLib.mkCity {
                inherit pkgs packToml;
                gcPackage = self.packages.${system}.gc;
                config = {
                  workspace.name = "test-city";
                  session.concurrentPerAgent = 3;
                  beads.prefix = "tc";
                  daemon.patrolInterval = "15s";
                  rigs.my-rig = {
                    path = "rigs/my-rig";
                    gitUrl = "git@github.com:test/rig.git";
                  };
                };
              };
            in
            pkgs.runCommand "check-city-toml" { nativeBuildInputs = [ pythonWithTomli ]; } ''
              python3 -c "
              import tomli, sys
              with open('${city.cityToml}', 'rb') as f:
                  data = tomli.load(f)

              # Validate workspace
              assert data['workspace']['name'] == 'test-city'
              assert data['workspace']['provider'] == 'local'

              # Validate session
              assert data['session']['provider'] == 'tmux'
              assert data['session']['concurrent_per_agent'] == 3

              # Validate beads
              assert data['beads']['provider'] == 'dolt'
              assert data['beads']['prefix'] == 'tc'

              # Validate daemon
              assert data['daemon']['patrol_interval'] == '15s'
              assert data['daemon']['max_restarts'] == 3
              assert data['daemon']['shutdown_timeout'] == '60s'

              # Validate rigs
              assert 'my-rig' in data['rigs'], f'rigs: {data[\"rigs\"]}'
              assert data['rigs']['my-rig']['path'] == 'rigs/my-rig'
              assert data['rigs']['my-rig']['git_url'] == 'git@github.com:test/rig.git'
              assert data['rigs']['my-rig']['default_branch'] == 'main'

              print('city.toml validation passed')
              "
              touch $out
            '';

          check-eval-pure =
            let
              packCfg = gastownLib.evalPack {
                config = {
                  name = "pure-pack";
                  agents.worker = {
                    scope = "rig";
                    maxConcurrent = 5;
                  };
                };
              };
              cityCfg = gastownLib.evalCity {
                config = {
                  workspace.name = "pure-city";
                  rigs.alpha = {
                    path = "rigs/alpha";
                    gitUrl = "git@github.com:test/alpha.git";
                  };
                };
              };
            in
            pkgs.runCommand "check-eval-pure" { } ''
              # Pack evaluation
              [[ "${packCfg.name}" == "pure-pack" ]]
              [[ "${toString packCfg.schema}" == "1" ]]

              # City evaluation
              [[ "${cityCfg.workspace.name}" == "pure-city" ]]
              [[ "${cityCfg.session.provider}" == "tmux" ]]
              [[ "${cityCfg.rigs.alpha.path}" == "rigs/alpha" ]]
              [[ "${cityCfg.rigs.alpha.gitUrl}" == "git@github.com:test/alpha.git" ]]
              [[ "${cityCfg.rigs.alpha.defaultBranch}" == "main" ]]

              echo "Pure evaluation checks passed"
              touch $out
            '';

          check-lifecycle-scripts =
            let
              packToml = gastownLib.mkPack {
                inherit pkgs;
                config = {
                  name = "lifecycle-test";
                  agents.mayor = {
                    scope = "town";
                    maxConcurrent = 1;
                  };
                };
              };
              city = gastownLib.mkCity {
                inherit pkgs packToml;
                gcPackage = self.packages.${system}.gc;
                config = {
                  workspace.name = "lifecycle-test";
                  rigs.test-rig = {
                    path = "rigs/test";
                    gitUrl = "git@github.com:test/lifecycle.git";
                  };
                };
              };
            in
            pkgs.runCommand "check-lifecycle-scripts" { } ''
              # Verify scripts exist and are executable
              test -x ${city.gcUp}/bin/gc-up
              test -x ${city.gcDown}/bin/gc-down
              test -x ${city.gcAttach}/bin/gc-attach

              # Verify scripts reference the TOML files
              grep -q "pack.toml" ${city.gcUp}/bin/gc-up
              grep -q "city.toml" ${city.gcUp}/bin/gc-up

              echo "Lifecycle scripts check passed"
              touch $out
            '';
        }
      );

      templates.default = {
        path = ./templates/default;
        description = "Embeddable Gas Town rig configuration";
      };
    };
}
