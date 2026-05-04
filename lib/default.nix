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
      git_url = rig.gitUrl;
      default_branch = rig.defaultBranch;
      mayor_crew = rig.mayorCrew;
      max_polecats = rig.maxPolecats;
      auto_restart = rig.autoRestart;
      auto_start_on_up = rig.autoStartOnUp;
      default_formula = rig.defaultFormula;
      dnd = rig.dnd;
      dolt_port = rig.doltPort;
      polecat_branch_template = rig.polecatBranchTemplate;
      priority_adjustment = rig.priorityAdjustment;
      beads = {
        prefix = rig.beads.prefix;
      };
      crew = mapAttrs crewToValue rig.crew;
    };

  crewToValue = _name: member:
    filterAttrs (_: v: v != null) {
      role = member.role;
      github_username = member.githubUsername;
      email = member.email;
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
      runtimeDeps = [
        pkgs.git
        pkgs.tmux
        gcPackage
      ];

      gcUp = pkgs.writeShellScriptBin "gc-up" ''
        set -euo pipefail
        export PATH="${lib.makeBinPath runtimeDeps}:$PATH"

        PROJECT_ROOT="$(git rev-parse --show-toplevel)"
        export GC_ROOT="$PROJECT_ROOT/.gt"

        # Step 1: Install TOML
        echo "Installing configuration..."
        mkdir -p "$GC_ROOT"
        install -m 644 ${packToml} "$GC_ROOT/pack.toml"
        install -m 644 ${cityToml} "$GC_ROOT/city.toml"

        # Step 2: gc init
        echo "Initializing workspace..."
        ${gcPackage}/bin/gc init

        # Step 3: gc up
        echo "Starting services..."
        ${gcPackage}/bin/gc up
      '';

      gcDown = pkgs.writeShellScriptBin "gc-down" ''
        set -euo pipefail
        export PATH="${lib.makeBinPath runtimeDeps}:$PATH"

        PROJECT_ROOT="$(git rev-parse --show-toplevel)"
        export GC_ROOT="$PROJECT_ROOT/.gt"

        ${gcPackage}/bin/gc down
      '';

      gcAttach = pkgs.writeShellScriptBin "gc-attach" ''
        set -euo pipefail
        export PATH="${lib.makeBinPath runtimeDeps}:$PATH"

        PROJECT_ROOT="$(git rev-parse --show-toplevel)"
        export GC_ROOT="$PROJECT_ROOT/.gt"

        ${gcPackage}/bin/gc mayor attach
      '';
    in
    {
      config = cfg;
      inherit cityToml gcUp gcDown gcAttach;
    };
}
