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

          # Standalone rig checks
          eval-rig =
            let
              rig = gastownLib.mkRig {
                inherit pkgs;
                gtPackage = self.packages.${system}.gt;
                config = {
                  name = "my-rig";
                  gitUrl = "git@github.com:test/standalone.git";
                  beads.prefix = "sr";
                  maxPolecats = 3;
                  crew.alice = {
                    role = "developer";
                    githubUsername = "alice-gh";
                    email = "alice@example.com";
                  };
                };
              };
            in
            pkgs.runCommand "check-eval-rig" { nativeBuildInputs = [ pkgs.jq ]; } ''
              # rigs.json has single entry
              jq -e '.version == 1' ${rig.configDir}/rigs.json
              jq -e '.rigs["my-rig"].git_url == "git@github.com:test/standalone.git"' ${rig.configDir}/rigs.json
              jq -e '.rigs["my-rig"].beads.prefix == "sr"' ${rig.configDir}/rigs.json

              # settings/config.json
              jq -e '.type == "town-settings"' ${rig.configDir}/settings/config.json
              jq -e '.default_agent == "claude"' ${rig.configDir}/settings/config.json

              # rig config.json
              jq -e '.type == "rig"' ${rig.rigConfig}
              jq -e '.name == "my-rig"' ${rig.rigConfig}
              jq -e '.git_url == "git@github.com:test/standalone.git"' ${rig.rigConfig}

              # rig settings.json
              jq -e '.max_polecats == 3' ${rig.rigSettings}
              jq -e '.auto_restart == true' ${rig.rigSettings}

              # crew config
              jq -e '.type == "crew-member"' ${rig.crewConfigs.alice}
              jq -e '.name == "alice"' ${rig.crewConfigs.alice}
              jq -e '.role == "developer"' ${rig.crewConfigs.alice}
              jq -e '.github_username == "alice-gh"' ${rig.crewConfigs.alice}

              # configDir structure
              test -f ${rig.configDir}/rigs.json
              test -f ${rig.configDir}/settings/config.json
              test -f ${rig.configDir}/my-rig/config.json
              test -f ${rig.configDir}/my-rig/crew/alice/config.json

              echo "Standalone rig checks passed"
              touch $out
            '';

          eval-rig-minimal =
            let
              rig = gastownLib.mkRig {
                inherit pkgs;
                gtPackage = self.packages.${system}.gt;
                config = {
                  name = "minimal-rig";
                  gitUrl = "git@github.com:test/minimal-rig.git";
                  beads.prefix = "mr";
                };
              };
            in
            pkgs.runCommand "check-eval-rig-minimal" { nativeBuildInputs = [ pkgs.jq ]; } ''
              # Verify basic config
              jq -e '.rigs["minimal-rig"].git_url == "git@github.com:test/minimal-rig.git"' ${rig.configDir}/rigs.json
              jq -e '.rigs["minimal-rig"].beads.prefix == "mr"' ${rig.configDir}/rigs.json

              jq -e '.name == "minimal-rig"' ${rig.rigConfig}
              jq -e '.default_branch == "main"' ${rig.rigConfig}

              # Verify defaults apply
              jq -e '.max_polecats == 10' ${rig.rigSettings}
              jq -e '.auto_restart == true' ${rig.rigSettings}
              jq -e '.default_formula == "mol-polecat-work"' ${rig.rigSettings}

              # No crew members
              jq -e '.crew == {}' ${rig.rigConfig}

              echo "Minimal standalone rig checks passed"
              touch $out
            '';

          eval-rig-pure =
            let
              cfg = gastownLib.evalRig {
                config = {
                  name = "pure-rig";
                  gitUrl = "git@github.com:test/pure-rig.git";
                  beads.prefix = "pr";
                  crew.bob = {
                    role = "reviewer";
                    githubUsername = "bob-gh";
                  };
                };
              };
            in
            pkgs.runCommand "check-eval-rig-pure" { } ''
              [[ "${cfg.name}" == "pure-rig" ]]
              [[ "${cfg.gitUrl}" == "git@github.com:test/pure-rig.git" ]]
              [[ "${cfg.beads.prefix}" == "pr" ]]
              [[ "${cfg.crew.bob.role}" == "reviewer" ]]
              [[ "${cfg.crew.bob.githubUsername}" == "bob-gh" ]]

              # mayorCrew auto-selects when exactly one crew member
              [[ "${cfg.mayorCrew}" == "bob" ]]

              echo "Pure rig evaluation checks passed"
              touch $out
            '';

          eval-rig-mayor-crew =
            let
              cfg = gastownLib.evalRig {
                config = {
                  name = "mc-rig";
                  gitUrl = "git@github.com:test/mc.git";
                  beads.prefix = "mc";
                  mayorCrew = "dev2";
                  crew = {
                    dev1 = { role = "developer"; };
                    dev2 = { role = "lead"; };
                  };
                };
              };
            in
            pkgs.runCommand "check-eval-rig-mayor-crew" { } ''
              # Explicit mayorCrew takes precedence
              [[ "${cfg.mayorCrew}" == "dev2" ]]

              echo "Mayor crew selection checks passed"
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
