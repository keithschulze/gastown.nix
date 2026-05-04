{ lib }:
let
  inherit (lib)
    evalModules
    filterAttrs
    mapAttrs
    ;

  doEvalPack =
    modules:
    (evalModules {
      modules = [ ../modules/pack.nix ] ++ modules;
      specialArgs = { inherit lib; };
    }).config;

  doEvalCity =
    modules:
    (evalModules {
      modules = [ ../modules/city.nix ] ++ modules;
      specialArgs = { inherit lib; };
    }).config;

  # Convert evaluated pack config to TOML-serialisable attrset
  packToValue = cfg: {
    pack = {
      name = cfg.name;
      schema = cfg.schema;
    };
    agents = mapAttrs (_: a: {
      scope = a.scope;
      provider = a.provider;
      max_concurrent = a.maxConcurrent;
    }) cfg.agents;
  };

  # Convert evaluated city config to TOML-serialisable attrset
  cityToValue = cfg: {
    workspace = {
      name = cfg.workspace.name;
      provider = cfg.workspace.provider;
    };
    session = {
      provider = cfg.session.provider;
      concurrent_per_agent = cfg.session.concurrentPerAgent;
    };
    beads = {
      provider = cfg.beads.provider;
      prefix = cfg.beads.prefix;
    };
    daemon = {
      patrol_interval = cfg.daemon.patrolInterval;
      max_restarts = cfg.daemon.maxRestarts;
      shutdown_timeout = cfg.daemon.shutdownTimeout;
    };
    rigs = mapAttrs rigToValue cfg.rigs;
  };

  rigToValue = _name: rig:
    filterAttrs (_: v: v != null) {
      path = rig.path;
      git_url = rig.gitUrl;
      default_branch = rig.defaultBranch;
    };

in
{
  # Evaluate pack config (agent definitions). Pure — no pkgs required.
  evalPack =
    {
      modules ? [ ],
      config ? { },
    }:
    doEvalPack ([ { config = config; } ] ++ modules);

  # Generate pack.toml via pkgs.formats.toml.
  mkPack =
    {
      pkgs,
      modules ? [ ],
      config ? { },
    }:
    let
      cfg = doEvalPack ([ { config = config; } ] ++ modules);
      fmt = pkgs.formats.toml { };
    in
    fmt.generate "${cfg.name}-pack.toml" (packToValue cfg);

  # Evaluate city config (runtime settings). Pure — no pkgs required.
  evalCity =
    {
      modules ? [ ],
      config ? { },
    }:
    doEvalCity ([ { config = config; } ] ++ modules);

  # Generate city.toml and lifecycle scripts (gcUp, gcDown, gcAttach).
  mkCity =
    {
      pkgs,
      gcPackage,
      packToml,
      modules ? [ ],
      config ? { },
    }:
    let
      cfg = doEvalCity ([ { config = config; } ] ++ modules);
      fmt = pkgs.formats.toml { };
      cityToml = fmt.generate "${cfg.workspace.name}-city.toml" (cityToValue cfg);
      # Shim: gc bundles bd but `gc start` checks for a standalone `bd` binary.
      bdShim = pkgs.writeShellScriptBin "bd" ''exec ${gcPackage}/bin/gc bd "$@"'';

      runtimeDeps = [
        pkgs.git
        pkgs.tmux
        pkgs.jq
        pkgs.dolt
        pkgs.lsof
        gcPackage
        bdShim
      ];

      gcUp = pkgs.writeShellScriptBin "gc-up" ''
        set -euo pipefail
        export PATH="${lib.makeBinPath runtimeDeps}:$PATH"

        PROJECT_ROOT="$(git rev-parse --show-toplevel)"
        export GC_ROOT="$PROJECT_ROOT/.gc"

        # Step 1: Install TOML
        echo "Installing configuration..."
        mkdir -p "$GC_ROOT"
        install -m 644 ${packToml} "$GC_ROOT/pack.toml"
        install -m 644 ${cityToml} "$GC_ROOT/city.toml"

        # Step 2: gc start (registers with supervisor + reconciles)
        echo "Starting services..."
        ${gcPackage}/bin/gc start
      '';

      gcDown = pkgs.writeShellScriptBin "gc-down" ''
        set -euo pipefail
        export PATH="${lib.makeBinPath runtimeDeps}:$PATH"

        PROJECT_ROOT="$(git rev-parse --show-toplevel)"
        export GC_ROOT="$PROJECT_ROOT/.gc"

        ${gcPackage}/bin/gc stop
      '';

      gcAttach = pkgs.writeShellScriptBin "gc-attach" ''
        set -euo pipefail
        export PATH="${lib.makeBinPath runtimeDeps}:$PATH"

        PROJECT_ROOT="$(git rev-parse --show-toplevel)"
        export GC_ROOT="$PROJECT_ROOT/.gc"

        ${gcPackage}/bin/gc mayor attach
      '';
    in
    {
      config = cfg;
      inherit cityToml gcUp gcDown gcAttach;
    };
}
