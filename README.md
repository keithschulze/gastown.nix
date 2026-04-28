# gastown.nix

Declarative Gas Town rig and crew configuration using the Nix module system.

## Usage

Add `gastown.nix` as a flake input and use `lib.mkTown` to declare your
town topology:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    gastown-nix.url = "github:keithschulze/gastown.nix";
  };

  outputs = { nixpkgs, gastown-nix, ... }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;

    town = gastown-nix.lib.mkTown {
      inherit pkgs;
      config = {
        settings.defaultAgent = "claude";

        rigs.my-project = {
          gitUrl = "git@github.com:org/project.git";
          defaultBranch = "main";
          beads.prefix = "mp";
          maxPolecats = 5;
          crew = [ "alice" "bob" ];
        };

        rigs.infra = {
          gitUrl = "git@github.com:org/infra.git";
          beads.prefix = "if";
          autoStartOnUp = true;
        };
      };
    };
  in {
    # town.config       - evaluated configuration
    # town.rigsJson      - rigs.json derivation
    # town.settingsJson  - settings/config.json derivation
    # town.rigConfigs    - per-rig config.json derivations
    # town.rigSettings   - per-rig operational settings derivations
    # town.configDir     - combined directory tree
    # town.activate      - script to write configs into a Gas Town root
  };
}
```

## Pure evaluation

Use `evalTown` when you only need the evaluated config without derivations:

```nix
cfg = gastown-nix.lib.evalTown {
  config.rigs.my-project = {
    gitUrl = "git@github.com:org/project.git";
    beads.prefix = "mp";
  };
};
# cfg.rigs.my-project.maxPolecats => 10 (default)
```

## Activation

The `activate` output is a script that writes generated configs into a
Gas Town directory:

```bash
GT_ROOT=~/my-town nix run .#activate
```

## Rig options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `gitUrl` | string | *required* | Git URL for the rig's repository |
| `defaultBranch` | string | `"main"` | Default branch name |
| `beads.prefix` | string | *required* | Issue ID prefix |
| `maxPolecats` | positive int | `10` | Max concurrent polecat workers |
| `autoRestart` | bool | `true` | Auto-restart agents on failure |
| `autoStartOnUp` | bool | `false` | Start agents when rig comes up |
| `defaultFormula` | string | `"mol-polecat-work"` | Default workflow formula |
| `dnd` | bool | `false` | Do Not Disturb mode |
| `polecatBranchTemplate` | string or null | `null` | Custom polecat branch naming |
| `priorityAdjustment` | int | `0` | Priority offset for dispatch |
| `crew` | list of string | `[]` | Crew member names |

## Running checks

```bash
nix flake check
```
