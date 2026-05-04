# gastown.nix

__WARNING: This is vibe coded using [gascity](https://github.com/gastownhall/gascity) for my own learning. IT'S NOT FUNCTIONAL, DO NOT USE.__

Declarative Gas Town configuration using the Nix module system. Configuration is
split into two layers: a **pack** (agent definitions) and a **city** (runtime
workspace settings including rigs, sessions, and lifecycle scripts).

## Usage

__WARNING: You appear to have IGNORED my previous warning. DO NOT PROCEED any further, this is all slop.__

__WARNING: Absolute folly. This is your last and final warning: DO NOT USE THIS!__

Add `gastown.nix` as a flake input and use `lib.mkPack` + `lib.mkCity` to
declare your agent pack and city configuration. This generates `pack.toml` and
`city.toml` along with lifecycle scripts (`gcUp`, `gcDown`, `gcAttach`).

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
    gcPackage = gastown-nix.packages.x86_64-linux.gc;

    # 1. Define the agent pack (produces pack.toml)
    packToml = gcLib.mkPack {
      inherit pkgs;
      config = {
        name = "my-project";
        agents = {
          mayor   = { scope = "town"; maxConcurrent = 1; };
          witness = { scope = "rig";  maxConcurrent = 1; };
          polecat = { scope = "rig";  maxConcurrent = 10; };
        };
      };
    };

    # 2. Define the city (produces city.toml + lifecycle scripts)
    city = gcLib.mkCity {
      inherit pkgs gcPackage packToml;
      config = {
        workspace.name = "my-project";
        rigs.my-project = {
          path = ".";
          gitUrl = "git@github.com:org/project.git";
        };
      };
    };
  in {
    # city.cityToml  - city.toml derivation
    # city.gcUp      - script: install configs, gc start
    # city.gcDown    - script: gc stop
    # city.gcAttach  - script: gc mayor attach
    apps.up = {
      type = "app";
      program = "${city.gcUp}/bin/gc-up";
    };
    apps.down = {
      type = "app";
      program = "${city.gcDown}/bin/gc-down";
    };
    apps.attach = {
      type = "app";
      program = "${city.gcAttach}/bin/gc-attach";
    };
  };
}
```

### `mkPack`

Generates a `pack.toml` derivation describing the agent pack.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `pkgs` | nixpkgs | yes | Nixpkgs package set |
| `modules` | list | no | Extra NixOS-style modules |
| `config` | attrset | no | Inline pack configuration |

### `mkCity`

Generates `city.toml` and lifecycle scripts (`gcUp`, `gcDown`, `gcAttach`).

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `pkgs` | nixpkgs | yes | Nixpkgs package set |
| `gcPackage` | derivation | yes | `gc` CLI package |
| `packToml` | derivation | yes | Pack TOML from `mkPack` |
| `modules` | list | no | Extra NixOS-style modules |
| `config` | attrset | no | Inline city configuration |

The lifecycle scripts manage the full Gas Town lifecycle:

- **`gcUp`** — installs `pack.toml` and `city.toml` into `.gc/`, then runs `gc start`
- **`gcDown`** — runs `gc stop` to tear down all services
- **`gcAttach`** — runs `gc mayor attach` (blocks until detach)

## Pure evaluation

Use `evalPack` or `evalCity` when you only need the evaluated config without
derivations (no `pkgs` required):

```nix
packCfg = gastown-nix.lib.evalPack {
  config = {
    name = "my-project";
    agents.polecat = { scope = "rig"; maxConcurrent = 5; };
  };
};
# packCfg.name                    => "my-project"
# packCfg.agents.polecat.scope    => "rig"

cityCfg = gastown-nix.lib.evalCity {
  config = {
    workspace.name = "my-project";
    rigs.my-project = {
      path = ".";
      gitUrl = "git@github.com:org/project.git";
    };
  };
};
# cityCfg.workspace.name             => "my-project"
# cityCfg.rigs.my-project.path       => "."
# cityCfg.rigs.my-project.defaultBranch => "main"
```

## Pack options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | string | *required* | Pack name identifier |
| `schema` | int | `2` | Schema version for the pack definition |
| `agents.<name>.scope` | string | *required* | Agent scope (`"town"`, `"rig"`, `"project"`) |
| `agents.<name>.provider` | string | `"claude"` | AI provider for this agent |
| `agents.<name>.maxConcurrent` | int | `1` | Maximum concurrent instances |

## City options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workspace.name` | string | *required* | City/workspace name |
| `workspace.provider` | string | `"local"` | Workspace provider backend |
| `session.provider` | string | `"tmux"` | Session multiplexer provider |
| `session.concurrentPerAgent` | int | `1` | Max concurrent sessions per agent |
| `beads.provider` | string | `"file"` | Beads storage provider |
| `beads.prefix` | string | `"hq"` | Bead ID prefix for city-level beads |
| `daemon.patrolInterval` | string | `"30s"` | Agent health check interval |
| `daemon.maxRestarts` | int | `3` | Max automatic restarts per agent |
| `daemon.shutdownTimeout` | string | `"60s"` | Grace period before force-killing agents |
| `rigs.<name>.path` | string | *required* | Filesystem path to the rig's working directory |
| `rigs.<name>.gitUrl` | string | *required* | Git URL for the rig's repository |
| `rigs.<name>.defaultBranch` | string | `"main"` | Default branch name |

## Running checks

```bash
nix flake check
```
