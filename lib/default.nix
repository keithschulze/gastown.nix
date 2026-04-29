{ lib }:
let
  inherit (lib)
    evalModules
    mapAttrs
    mapAttrsToList
    concatStringsSep
    filterAttrs
    ;

  # Convert a crew member config to its JSON representation
  crewMemberToConfig = name: memberCfg:
    filterAttrs (_: v: v != null) {
      type = "crew-member";
      version = 1;
      inherit name;
      role = memberCfg.role;
      github_username = memberCfg.githubUsername;
      email = memberCfg.email;
    };

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
    crew = mapAttrs crewMemberToConfig rigCfg.crew;
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

  # Shared evaluation logic for standalone rig
  doEval = modules:
    (evalModules {
      modules = [ ../modules/standalone.nix ] ++ modules;
      specialArgs = { inherit lib; };
    }).config;

in
{
  # Evaluate rig configuration (pure, no pkgs required).
  # Returns the evaluated config attrset.
  evalRig =
    {
      modules ? [ ],
      config ? { },
    }:
    doEval ([ { config = config; } ] ++ modules);

  # Create a standalone rig with generated derivations.
  # Returns config, JSON file derivations, a combined configDir, an
  # activation script, and a mayorAttach script.
  mkRig =
    {
      pkgs,
      gtPackage,
      bdPackage ? null,
      modules ? [ ],
      config ? { },
    }:
    let
      cfg = doEval ([ { config = config; } ] ++ modules);
      rigName = cfg.name;

      rigsJsonFile = pkgs.writeText "rigs.json" (builtins.toJSON {
        version = 1;
        rigs.${rigName} = rigToRegistryEntry rigName cfg;
      });

      settingsJsonFile = pkgs.writeText "town-settings.json" (
        builtins.toJSON (settingsToConfig { defaultAgent = cfg.defaultAgent; })
      );

      rigConfigFile = pkgs.writeText "${rigName}-config.json" (
        builtins.toJSON (rigToConfig rigName cfg)
      );

      rigSettingsFile = pkgs.writeText "${rigName}-settings.json" (
        builtins.toJSON (rigToSettings cfg)
      );

      crewConfigFileSet = mapAttrs (
        memberName: memberCfg:
        pkgs.writeText "${rigName}-crew-${memberName}-config.json" (
          builtins.toJSON (crewMemberToConfig memberName memberCfg)
        )
      ) cfg.crew;

      crewActivations = concatStringsSep "\n" (
        mapAttrsToList (member: _memberCfg: ''
          mkdir -p "$GT_ROOT/${rigName}/crew/${member}"
          install -m 644 ${crewConfigFileSet.${member}} "$GT_ROOT/${rigName}/crew/${member}/config.json"
        '') cfg.crew
      );

    in
    {
      config = cfg;

      rigConfig = rigConfigFile;
      rigSettings = rigSettingsFile;
      crewConfigs = crewConfigFileSet;

      configDir = pkgs.runCommand "gt-rig-config" { } ''
        mkdir -p $out/settings
        cp ${rigsJsonFile} $out/rigs.json
        cp ${settingsJsonFile} $out/settings/config.json
        mkdir -p $out/${rigName}
        cp ${rigConfigFile} $out/${rigName}/config.json
        ${concatStringsSep "\n" (
          mapAttrsToList (memberName: _memberCfg: ''
            mkdir -p $out/${rigName}/crew/${memberName}
            cp ${crewConfigFileSet.${memberName}} $out/${rigName}/crew/${memberName}/config.json
          '') cfg.crew
        )}
      '';

      activate = pkgs.writeShellScriptBin "gt-activate" ''
        set -euo pipefail
        GT_ROOT="''${GT_ROOT:-.}"
        echo "Activating rig ${rigName} at $GT_ROOT"

        mkdir -p "$GT_ROOT/settings"
        install -m 644 ${rigsJsonFile} "$GT_ROOT/rigs.json"
        install -m 644 ${settingsJsonFile} "$GT_ROOT/settings/config.json"

        mkdir -p "$GT_ROOT/${rigName}"
        install -m 644 ${rigConfigFile} "$GT_ROOT/${rigName}/config.json"

        ${crewActivations}

        echo "Done."
      '';

      mayorAttach =
        let
          crewMember = cfg.mayorCrew;
          hasCrewMember = crewMember != null;
          runtimeDeps = [ pkgs.git pkgs.tmux gtPackage ]
            ++ lib.optional (bdPackage != null) bdPackage;
        in
        assert hasCrewMember;
        pkgs.writeShellScriptBin "gt-mayor-attach" ''
          set -euo pipefail
          export PATH="${lib.makeBinPath runtimeDeps}:$PATH"

          # 1. Discover project root
          PROJECT_ROOT="$(git rev-parse --show-toplevel)"

          # 2. Set GT_ROOT and GT_TOWN_ROOT
          export GT_ROOT="$PROJECT_ROOT/.gt"
          export GT_TOWN_ROOT="$GT_ROOT"

          # 3. Activate nix-generated config into .gt/
          echo "Activating rig ${rigName} at $GT_ROOT"
          mkdir -p "$GT_ROOT/settings"
          install -m 644 ${rigsJsonFile} "$GT_ROOT/rigs.json"
          install -m 644 ${settingsJsonFile} "$GT_ROOT/settings/config.json"
          mkdir -p "$GT_ROOT/${rigName}"
          install -m 644 ${rigConfigFile} "$GT_ROOT/${rigName}/config.json"
          ${crewActivations}

          # 4. Ensure crew state.json exists
          CREW_DIR="$GT_ROOT/${rigName}/crew/${crewMember}"
          mkdir -p "$CREW_DIR"
          if [ ! -f "$CREW_DIR/state.json" ]; then
            NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            cat > "$CREW_DIR/state.json" <<STATE
          {
            "name": "${crewMember}",
            "rig": "${rigName}",
            "clone_path": "$PROJECT_ROOT",
            "branch": "$(git rev-parse --abbrev-ref HEAD)",
            "created_at": "$NOW",
            "updated_at": "$NOW"
          }
          STATE
          fi

          # 5. cd to crew dir and exec gt mayor attach
          cd "$CREW_DIR"
          exec ${gtPackage}/bin/gt mayor attach
        '';
    };
}
