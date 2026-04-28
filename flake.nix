{
  description = "Nix packaging and declarative configuration for Gas Town";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    gastown-src = {
      url = "github:gastownhall/gastown";
      flake = false;
    };

    beads-src = {
      url = "github:gastownhall/beads";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      gastown-src,
      beads-src,
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
          bdBase = pkgs.buildGoModule {
            pname = "beads";
            version = "1.0.3";
            src = beads-src;

            subPackages = [ "cmd/bd" ];
            tags = [ "gms_pure_go" ];
            doCheck = false;

            proxyVendor = true;
            vendorHash = "sha256-FjO7mUTB9FJL5ShVzEj+dEr1Hpzb23JO5QjNLPc5sLQ=";

            postPatch = ''
              goVer="$(go env GOVERSION | sed 's/^go//')"
              go mod edit -go="$goVer"
            '';

            env.GOTOOLCHAIN = "auto";

            nativeBuildInputs = [ pkgs.git ];

            meta = with pkgs.lib; {
              description = "beads (bd) - issue tracker for AI-supervised coding workflows";
              homepage = "https://github.com/gastownhall/beads";
              license = licenses.mit;
              mainProgram = "bd";
            };
          };

          bd = pkgs.stdenv.mkDerivation {
            pname = "beads";
            version = bdBase.version;
            phases = [ "installPhase" ];
            installPhase = ''
              mkdir -p $out/bin
              cp ${bdBase}/bin/bd $out/bin/bd
              ln -s bd $out/bin/beads

              mkdir -p $out/share/fish/vendor_completions.d
              mkdir -p $out/share/bash-completion/completions
              mkdir -p $out/share/zsh/site-functions

              $out/bin/bd completion fish > $out/share/fish/vendor_completions.d/bd.fish
              $out/bin/bd completion bash > $out/share/bash-completion/completions/bd
              $out/bin/bd completion zsh > $out/share/zsh/site-functions/_bd
            '';
            meta = bdBase.meta;
          };

          gt = pkgs.buildGoModule {
            pname = "gt";
            version = "1.0.0";
            src = gastown-src;

            subPackages = [ "cmd/gt" ];
            doCheck = false;

            proxyVendor = true;
            vendorHash = "sha256-ew4YoB1sn6FvPbxs29kqd2BUv/KO5Fy7JWHj/hKPEPs=";

            postPatch = ''
              goVer="$(go env GOVERSION | sed 's/^go//')"
              go mod edit -go="$goVer"
            '';

            env.GOTOOLCHAIN = "auto";

            ldflags = [
              "-s"
              "-w"
              "-X github.com/steveyegge/gastown/internal/cmd.Build=nix"
              "-X github.com/steveyegge/gastown/internal/cmd.BuiltProperly=1"
            ];

            meta = with pkgs.lib; {
              description = "Gas Town - multi-agent orchestration for Claude Code";
              homepage = "https://github.com/gastownhall/gastown";
              license = licenses.mit;
              mainProgram = "gt";
            };
          };
        in
        {
          inherit gt bd;
          default = gt;
        }
      );

      apps = forAllSystems (
        { system, ... }:
        {
          gt = {
            type = "app";
            program = "${self.packages.${system}.gt}/bin/gt";
          };
          bd = {
            type = "app";
            program = "${self.packages.${system}.bd}/bin/bd";
          };
          default = self.apps.${system}.gt;
        }
      );

      devShells = forAllSystems (
        { pkgs, system }:
        {
          default = pkgs.mkShell {
            buildInputs = [
              self.packages.${system}.gt
              self.packages.${system}.bd
            ];
          };
        }
      );

      checks = forAllSystems (
        { pkgs, system }:
        {
          eval-default =
            let
              town = gastownLib.mkTown {
                inherit pkgs;
                config = {
                  settings.defaultAgent = "claude";
                  rigs.test-rig = {
                    gitUrl = "git@github.com:test/repo.git";
                    defaultBranch = "main";
                    beads.prefix = "tr";
                    maxPolecats = 5;
                    crew.alice = {
                      role = "developer";
                      githubUsername = "alice-gh";
                    };
                  };
                };
              };
            in
            pkgs.runCommand "check-eval-default" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '.version == 1' ${town.rigsJson}
              jq -e '.rigs["test-rig"].git_url == "git@github.com:test/repo.git"' ${town.rigsJson}
              jq -e '.rigs["test-rig"].beads.prefix == "tr"' ${town.rigsJson}

              jq -e '.type == "town-settings"' ${town.settingsJson}
              jq -e '.default_agent == "claude"' ${town.settingsJson}

              jq -e '.type == "rig"' ${town.rigConfigs.test-rig}
              jq -e '.name == "test-rig"' ${town.rigConfigs.test-rig}
              jq -e '.default_branch == "main"' ${town.rigConfigs.test-rig}
              jq -e '.git_url == "git@github.com:test/repo.git"' ${town.rigConfigs.test-rig}

              jq -e '.auto_restart == true' ${town.rigSettings.test-rig}
              jq -e '.max_polecats == 5' ${town.rigSettings.test-rig}
              jq -e '.default_formula == "mol-polecat-work"' ${town.rigSettings.test-rig}

              # Crew member config in rig config.json
              jq -e '.crew.alice.name == "alice"' ${town.rigConfigs.test-rig}
              jq -e '.crew.alice.role == "developer"' ${town.rigConfigs.test-rig}
              jq -e '.crew.alice.github_username == "alice-gh"' ${town.rigConfigs.test-rig}

              # Per-member config file
              jq -e '.type == "crew-member"' ${town.crewConfigs.test-rig.alice}
              jq -e '.name == "alice"' ${town.crewConfigs.test-rig.alice}
              jq -e '.role == "developer"' ${town.crewConfigs.test-rig.alice}
              jq -e '.github_username == "alice-gh"' ${town.crewConfigs.test-rig.alice}

              test -f ${town.configDir}/rigs.json
              test -f ${town.configDir}/settings/config.json
              test -f ${town.configDir}/test-rig/config.json
              test -f ${town.configDir}/test-rig/crew/alice/config.json

              echo "All checks passed"
              touch $out
            '';

          eval-minimal =
            let
              town = gastownLib.mkTown {
                inherit pkgs;
                config = {
                  rigs.minimal = {
                    gitUrl = "git@github.com:test/minimal.git";
                    beads.prefix = "mn";
                  };
                };
              };
            in
            pkgs.runCommand "check-eval-minimal" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '.rigs.minimal.git_url == "git@github.com:test/minimal.git"' ${town.rigsJson}
              jq -e '.default_agent == "claude"' ${town.settingsJson}
              jq -e '.default_branch == "main"' ${town.rigConfigs.minimal}

              jq -e '.max_polecats == 10' ${town.rigSettings.minimal}
              jq -e '.auto_restart == true' ${town.rigSettings.minimal}

              echo "Minimal config checks passed"
              touch $out
            '';

          eval-pure =
            let
              cfg = gastownLib.evalTown {
                config = {
                  rigs.pure-test = {
                    gitUrl = "git@github.com:test/pure.git";
                    beads.prefix = "pt";
                    crew = {
                      dev1 = {
                        role = "developer";
                        email = "dev1@example.com";
                      };
                      dev2 = {
                        role = "reviewer";
                        githubUsername = "dev2-gh";
                      };
                    };
                  };
                };
              };
            in
            pkgs.runCommand "check-eval-pure" { } ''
              [[ "${cfg.rigs.pure-test.gitUrl}" == "git@github.com:test/pure.git" ]]
              [[ "${cfg.rigs.pure-test.beads.prefix}" == "pt" ]]
              [[ "${cfg.settings.defaultAgent}" == "claude" ]]

              # Crew member evaluation
              [[ "${cfg.rigs.pure-test.crew.dev1.role}" == "developer" ]]
              [[ "${cfg.rigs.pure-test.crew.dev1.email}" == "dev1@example.com" ]]
              [[ "${cfg.rigs.pure-test.crew.dev2.role}" == "reviewer" ]]
              [[ "${cfg.rigs.pure-test.crew.dev2.githubUsername}" == "dev2-gh" ]]

              echo "Pure evaluation checks passed"
              touch $out
            '';
        }
      );

      templates.default = {
        path = ./templates/default;
        description = "Gas Town project configuration using flake-utils";
      };
    };
}
