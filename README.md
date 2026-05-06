# gastown.nix

__WARNING: This is vibe coded using [gascity](https://github.com/gastownhall/gascity) for my own learning. IT'S NOT FUNCTIONAL, DO NOT USE.__

Declarative authoring of [Gas City](https://github.com/gastownhall/gascity)
pack and city configuration via the Nix module system. The flake produces a
filesystem tree (`pack.toml` + `agents/<name>/...` + `city.toml`) that you drop
into a Gas City workspace; it does **not** ship `gc`, `bd`, `tmux`, or any
runtime — assume those are present on the host.

## Usage

__WARNING: You appear to have IGNORED my previous warning. DO NOT PROCEED any further, this is all slop.__

__WARNING: Absolute folly. This is your last and final warning: DO NOT USE THIS!__

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    gastown-nix.url = "github:keithschulze/gastown.nix";
  };

  outputs = { self, nixpkgs, gastown-nix, ... }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
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
  in {
    packages.x86_64-linux = {
      inherit pack;
      city = city.tree;
    };
  };
}
```

`nix build .#city` produces a directory containing everything Gas City needs.
Copy it into a workspace (`cp -r ./result/. ~/my-project/`), then run
`gc init` / `gc start` on the host.

### `mkPack`

Builds a directory derivation containing `pack.toml` and an `agents/<name>/`
subtree (one `prompt.template.md` per declared agent, plus `agent.toml` when
overrides are set).

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `pkgs` | nixpkgs | yes | Nixpkgs package set |
| `modules` | list | no | Extra NixOS-style modules |
| `config` | attrset | no | Inline pack configuration |

### `mkCity`

Builds `city.toml` and a `tree` derivation that merges the pack tree with
`city.toml`.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `pkgs` | nixpkgs | yes | Nixpkgs package set |
| `pack` | derivation | yes | Pack tree from `mkPack` |
| `modules` | list | no | Extra NixOS-style modules |
| `config` | attrset | no | Inline city configuration |

Returns `{ config, cityToml, pack, tree }`. `tree` is the install root.

## Pure evaluation

Use `evalPack` / `evalCity` when you only need the evaluated config (no `pkgs`
required):

```nix
packCfg = gastown-nix.lib.evalPack {
  config = {
    name = "my-project";
    agents.worker.promptTemplate = "# Worker\n";
  };
};
# packCfg.name                            => "my-project"
# packCfg.agents.worker.promptTemplate    => "# Worker\n"

cityCfg = gastown-nix.lib.evalCity {
  config = {
    workspace.provider = "claude";
    rigs = [ "my-project" ];
  };
};
# cityCfg.workspace.provider => "claude"
# cityCfg.rigs               => [ "my-project" ]
```

## Pack options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | string | *required* | Pack name (`pack.name`) |
| `schema` | int | `2` | Pack schema version |
| `agents.<name>.promptTemplate` | path or lines | `null` | Markdown prompt for the agent. When non-null, an `[[agent]]` block is emitted; when null the agent is presumed inherited from an imported pack. |
| `agents.<name>.dir` | string | `null` | Working-directory override (`dir` in `agent.toml`) |
| `agents.<name>.provider` | string | `null` | Provider override (`claude`, `codex`, ...) |
| `agents.<name>.optionDefaults` | attrset | `{}` | `option_defaults = { ... }` table in `agent.toml` |
| `agents.<name>.extraAgentToml` | attrset | `{}` | Escape hatch for un-modelled `agent.toml` fields |
| `namedSessions[*].template` | string | *required* | Agent name this session is templated from |
| `namedSessions[*].mode` | enum | `"always"` | One of `always`, `on_demand`, `never` |
| `namedSessions[*].scope` | enum or null | `null` | One of `city`, `rig` |
| `extraPackToml` | attrset | `{}` | Escape hatch for un-modelled `pack.toml` sections |

## City options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workspace.provider` | string | `"claude"` | Coding-agent provider for the workspace |
| `rigs` | list of string | `[]` | Rig names; each becomes a `[[rigs]]` block |
| `extraCityToml` | attrset | `{}` | Escape hatch for un-modelled `city.toml` fields |

## What this does NOT model

The Nix layer only authors what belongs in `pack.toml`, `city.toml`, and
`agents/<name>/`. The rest of a Gas City workspace is user-managed:

- `formulas/`, `orders/`, `commands/`, `doctor/`, `template-fragments/`,
  `overlay/`, `assets/` — copy or commit alongside the generated tree.
- `.gc/site.toml` — machine-local workspace identity and rig path bindings,
  populated by `gc init` and `gc rig add`.
- `[imports.*]`, `[global]`, `[[patches.agent]]` and similar `pack.toml`
  sections — reach for `extraPackToml` if you need them.

## Running checks

```bash
nix flake check
```
