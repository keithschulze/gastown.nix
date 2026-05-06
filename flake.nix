{
  description = "Declarative Gas City pack and city configuration for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
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

      # Dogfood: gt_nix pack + city, mayor-only.
      mkDogfood =
        pkgs:
        let
          pack = gastownLib.mkPack {
            inherit pkgs;
            config = {
              name = "gt_nix";
              agents.mayor = {
                promptTemplate = ./agents/mayor/prompt.template.md;
              };
              namedSessions = [
                { template = "mayor"; mode = "always"; scope = "city"; }
              ];
            };
          };
          city = gastownLib.mkCity {
            inherit pkgs pack;
            config = {
              workspace.provider = "claude";
              rigs = [ "gt_nix" ];
            };
          };
        in
        { inherit pack city; };
    in
    {
      lib = gastownLib;

      packages = forAllSystems (
        { pkgs, system }:
        let
          dogfood = mkDogfood pkgs;
        in
        {
          pack = dogfood.pack;
          city = dogfood.city.tree;
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
              pack = gastownLib.mkPack {
                inherit pkgs;
                config = {
                  name = "test-pack";
                  agents = {
                    mayor.promptTemplate = "# Mayor\n";
                    witness = {
                      promptTemplate = "# Witness\n";
                      dir = ".";
                      optionDefaults = {
                        model = "sonnet";
                        permission_mode = "plan";
                      };
                    };
                    # Prompt-less agent: only emits agents/imported/agent.toml,
                    # used for tweaking an agent inherited from an imported pack.
                    imported = {
                      extraAgentToml = {
                        wake_mode = "manual";
                      };
                    };
                  };
                  namedSessions = [
                    { template = "mayor"; mode = "always"; scope = "city"; }
                    { template = "witness"; mode = "always"; scope = "rig"; }
                  ];
                  extraPackToml = {
                    imports.maintenance.source = "../maintenance";
                  };
                };
              };
            in
            pkgs.runCommand "check-pack-toml" { nativeBuildInputs = [ pythonWithTomli ]; } ''
              python3 -c "
              import tomli
              with open('${pack}/pack.toml', 'rb') as f:
                  data = tomli.load(f)

              assert data['pack']['name'] == 'test-pack', data['pack']
              assert data['pack']['schema'] == 2, data['pack']

              names = sorted(a['name'] for a in data['agent'])
              # 'imported' has no promptTemplate so no [[agent]] block
              assert names == ['mayor', 'witness'], names
              for a in data['agent']:
                  assert a['prompt_template'] == f'agents/{a[\"name\"]}/prompt.template.md', a

              sessions = data['named_session']
              assert len(sessions) == 2, sessions
              assert sessions[0]['template'] == 'mayor'
              assert sessions[0]['mode'] == 'always'
              assert sessions[0]['scope'] == 'city'

              # extraPackToml escape hatch is honoured
              assert data['imports']['maintenance']['source'] == '../maintenance', data

              # Spec compliance: removed fields must not appear
              assert 'agents' not in data, 'pack.toml must not have [agents] table'
              for a in data['agent']:
                  assert 'scope' not in a, a
                  assert 'max_concurrent' not in a, a
                  assert 'provider' not in a, a

              print('pack.toml validation passed')
              "

              # Tree shape
              test -f ${pack}/pack.toml
              test -f ${pack}/agents/mayor/prompt.template.md
              test -f ${pack}/agents/witness/prompt.template.md
              test -f ${pack}/agents/witness/agent.toml
              ! test -e ${pack}/agents/mayor/agent.toml

              # Prompt-less agent: agent.toml only, no prompt.template.md
              test -f ${pack}/agents/imported/agent.toml
              ! test -e ${pack}/agents/imported/prompt.template.md
              python3 -c "
              import tomli
              with open('${pack}/agents/imported/agent.toml', 'rb') as f:
                  data = tomli.load(f)
              assert data['wake_mode'] == 'manual', data
              "

              python3 -c "
              import tomli
              with open('${pack}/agents/witness/agent.toml', 'rb') as f:
                  data = tomli.load(f)
              assert data['dir'] == '.'
              assert data['option_defaults']['model'] == 'sonnet'
              assert data['option_defaults']['permission_mode'] == 'plan'
              print('agent.toml validation passed')
              "

              touch $out
            '';

          check-city-toml =
            let
              pack = gastownLib.mkPack {
                inherit pkgs;
                config = {
                  name = "city-test";
                  agents.mayor.promptTemplate = "# Mayor\n";
                };
              };
              city = gastownLib.mkCity {
                inherit pkgs pack;
                config = {
                  workspace.provider = "codex";
                  rigs = [ "alpha" "beta" ];
                };
              };
            in
            pkgs.runCommand "check-city-toml" { nativeBuildInputs = [ pythonWithTomli ]; } ''
              python3 -c "
              import tomli
              with open('${city.cityToml}', 'rb') as f:
                  data = tomli.load(f)

              assert data['workspace']['provider'] == 'codex', data
              assert 'name' not in data['workspace'], 'workspace.name lives in site.toml'

              rig_names = [r['name'] for r in data['rigs']]
              assert rig_names == ['alpha', 'beta'], rig_names

              # Spec compliance: removed sections must not appear
              for forbidden in ('session', 'beads', 'daemon'):
                  assert forbidden not in data, f'city.toml must not have [{forbidden}]'

              print('city.toml validation passed')
              "

              # Tree shape: city tree contains pack contents + city.toml
              test -f ${city.tree}/city.toml
              test -f ${city.tree}/pack.toml
              test -f ${city.tree}/agents/mayor/prompt.template.md

              touch $out
            '';

          check-eval-pure =
            let
              packCfg = gastownLib.evalPack {
                config = {
                  name = "pure-pack";
                  agents.worker.promptTemplate = "# Worker\n";
                  namedSessions = [
                    { template = "worker"; mode = "on_demand"; scope = "rig"; }
                  ];
                };
              };
              cityCfg = gastownLib.evalCity {
                config = {
                  workspace.provider = "claude";
                  rigs = [ "alpha" ];
                };
              };
            in
            pkgs.runCommand "check-eval-pure" { } ''
              [[ "${packCfg.name}" == "pure-pack" ]]
              [[ "${toString packCfg.schema}" == "2" ]]
              [[ "${packCfg.agents.worker.promptTemplate}" == "# Worker
" ]]
              [[ "${(builtins.head packCfg.namedSessions).template}" == "worker" ]]
              [[ "${(builtins.head packCfg.namedSessions).mode}" == "on_demand" ]]

              [[ "${cityCfg.workspace.provider}" == "claude" ]]
              [[ "${builtins.head cityCfg.rigs}" == "alpha" ]]

              echo "Pure evaluation checks passed"
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
