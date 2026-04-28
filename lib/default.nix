{ lib }:
let
  inherit (lib)
    evalModules
    mapAttrs
    mapAttrsToList
    concatStringsSep
    filterAttrs
    ;

  # Convert evaluated rig config to a rigs.json registry entry
  rigToRegistryEntry = _name: rigCfg: {
    git_url = rigCfg.gitUrl;
    beads = {
      repo = "";
      prefix = rigCfg.beads.prefix;
    };
  };

  # Convert evaluated rig config to per-rig config.json
  rigToConfig = name: rigCfg: {
    type = "rig";
    version = 1;
    inherit name;
    git_url = rigCfg.gitUrl;
    default_branch = rigCfg.defaultBranch;
    beads = {
      prefix = rigCfg.beads.prefix;
    };
  };

  # Convert rig config to operational settings (snake_case for gt CLI)
  rigToSettings = rigCfg:
    filterAttrs (_: v: v != null) {
      auto_restart = rigCfg.autoRestart;
      auto_start_on_up = rigCfg.autoStartOnUp;
      default_formula = rigCfg.defaultFormula;
      dnd = rigCfg.dnd;
      max_polecats = rigCfg.maxPolecats;
      polecat_branch_template = rigCfg.polecatBranchTemplate;
      priority_adjustment = rigCfg.priorityAdjustment;
    };

  # Convert town settings to settings/config.json format
  settingsToConfig = settings: {
    type = "town-settings";
    version = 1;
    default_agent = settings.defaultAgent;
  };

  # Shared evaluation logic
  doEval = modules:
    (evalModules {
      modules = [ ../modules/town.nix ] ++ modules;
      specialArgs = { inherit lib; };
    }).config;

in
{
  # Evaluate town configuration (pure, no pkgs required).
  # Returns the evaluated config attrset.
  evalTown =
    {
      modules ? [ ],
      config ? { },
    }:
    doEval ([ { config = config; } ] ++ modules);

  # Create a town with generated derivations.
  # Returns config, JSON file derivations, a combined configDir, and an
  # activation script.
  mkTown =
    {
      pkgs,
      modules ? [ ],
      config ? { },
    }:
    let
      cfg = doEval ([ { config = config; } ] ++ modules);

      rigsJsonFile = pkgs.writeText "rigs.json" (builtins.toJSON {
        version = 1;
        rigs = mapAttrs rigToRegistryEntry cfg.rigs;
      });

      settingsJsonFile = pkgs.writeText "town-settings.json" (
        builtins.toJSON (settingsToConfig cfg.settings)
      );

      rigConfigFiles = mapAttrs (
        name: rigCfg:
        pkgs.writeText "${name}-config.json" (builtins.toJSON (rigToConfig name rigCfg))
      ) cfg.rigs;

      rigSettingsFiles = mapAttrs (
        name: rigCfg:
        pkgs.writeText "${name}-settings.json" (builtins.toJSON (rigToSettings rigCfg))
      ) cfg.rigs;

      rigActivations = concatStringsSep "\n" (
        mapAttrsToList (
          name: rigCfg:
          let
            crewChecks = concatStringsSep "\n" (
              map (member: ''
                if [ ! -d "$GT_ROOT/${name}/crew/${member}" ]; then
                  echo "    crew '${member}' not initialised — run: gt crew add ${member}"
                fi
              '') rigCfg.crew
            );
          in
          ''
            echo "  rig: ${name}"
            mkdir -p "$GT_ROOT/${name}"
            install -m 644 ${rigConfigFiles.${name}} "$GT_ROOT/${name}/config.json"
            ${crewChecks}
          ''
        ) cfg.rigs
      );

    in
    {
      config = cfg;

      # Individual config file derivations
      rigsJson = rigsJsonFile;
      settingsJson = settingsJsonFile;
      rigConfigs = rigConfigFiles;
      rigSettings = rigSettingsFiles;

      # All config files combined into a directory tree
      configDir = pkgs.runCommand "gt-config" { } (
        ''
          mkdir -p $out/settings
          cp ${rigsJsonFile} $out/rigs.json
          cp ${settingsJsonFile} $out/settings/config.json
        ''
        + concatStringsSep "\n" (
          mapAttrsToList (name: _rigCfg: ''
            mkdir -p $out/${name}
            cp ${rigConfigFiles.${name}} $out/${name}/config.json
          '') cfg.rigs
        )
      );

      # Activation script: writes generated configs into a Gas Town root
      activate = pkgs.writeShellScriptBin "gt-activate" ''
        set -euo pipefail
        GT_ROOT="''${GT_ROOT:-.}"
        echo "Activating Gas Town configuration at $GT_ROOT"

        mkdir -p "$GT_ROOT/settings"
        install -m 644 ${rigsJsonFile} "$GT_ROOT/rigs.json"
        install -m 644 ${settingsJsonFile} "$GT_ROOT/settings/config.json"

        ${rigActivations}

        echo "Done."
      '';
    };
}
