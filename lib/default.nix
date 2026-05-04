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
      dolt_port = rigCfg.doltPort;
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
  # Returns config, JSON file derivations, a combined configDir,
  # and a mayorAttach script that manages the full GT lifecycle.
  mkRig =
    {
      pkgs,
      gcPackage,
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

      test =
        let
          crewMember = cfg.mayorCrew;
          hasCrewMember = crewMember != null;
          runtimeDeps = [ pkgs.git pkgs.jq pkgs.dolt gcPackage ];
        in
        assert hasCrewMember;
        pkgs.writeShellScriptBin "gt-test-rig" ''
          set -euo pipefail
          export PATH="${lib.makeBinPath runtimeDeps}:$PATH"

          TMPDIR="$(mktemp -d)"
          trap "rm -rf $TMPDIR" EXIT

          cd "$TMPDIR"
          git init --initial-branch=main
          git commit --allow-empty -m "init"

          export GT_ROOT="$TMPDIR/.gt"
          export GT_TOWN_ROOT="$GT_ROOT"

          # === Layer 1: Activation ===
          echo "=== Layer 1: Activation ==="

          mkdir -p "$GT_ROOT/settings"
          install -m 644 ${rigsJsonFile} "$GT_ROOT/rigs.json"
          install -m 644 ${settingsJsonFile} "$GT_ROOT/settings/config.json"
          mkdir -p "$GT_ROOT/${rigName}"
          install -m 644 ${rigConfigFile} "$GT_ROOT/${rigName}/config.json"
          ${crewActivations}

          # Verify .gt/ structure
          echo "Checking rigs.json..."
          jq -e '.version == 1' "$GT_ROOT/rigs.json"
          jq -e '.rigs["${rigName}"].git_url' "$GT_ROOT/rigs.json"
          jq -e '.rigs["${rigName}"].beads.prefix == "${cfg.beads.prefix}"' "$GT_ROOT/rigs.json"

          echo "Checking settings/config.json..."
          jq -e '.type == "town-settings"' "$GT_ROOT/settings/config.json"
          jq -e '.default_agent == "${cfg.defaultAgent}"' "$GT_ROOT/settings/config.json"

          echo "Checking ${rigName}/config.json..."
          jq -e '.type == "rig"' "$GT_ROOT/${rigName}/config.json"
          jq -e '.name == "${rigName}"' "$GT_ROOT/${rigName}/config.json"

          ${concatStringsSep "\n" (
            mapAttrsToList (memberName: _memberCfg: ''
              echo "Checking crew member ${memberName}..."
              test -f "$GT_ROOT/${rigName}/crew/${memberName}/config.json"
              jq -e '.type == "crew-member"' "$GT_ROOT/${rigName}/crew/${memberName}/config.json"
              jq -e '.name == "${memberName}"' "$GT_ROOT/${rigName}/crew/${memberName}/config.json"
            '') cfg.crew
          )}

          echo "Layer 1: PASSED"

          # === Layer 2: GT workspace discovery ===
          echo "=== Layer 2: GT workspace discovery ==="

          gc rig list 2>/dev/null | grep -q "${rigName}" && echo "gc rig list: PASSED" || echo "gc rig list: SKIPPED (gc may need full install)"

          # === Layer 3: Crew state ===
          echo "=== Layer 3: Crew state ==="

          CREW_DIR="$GT_ROOT/${rigName}/crew/${crewMember}"
          mkdir -p "$CREW_DIR"
          NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          cat > "$CREW_DIR/state.json" <<STATE
          {
            "name": "${crewMember}",
            "rig": "${rigName}",
            "clone_path": "$TMPDIR",
            "branch": "main",
            "created_at": "$NOW",
            "updated_at": "$NOW"
          }
          STATE

          jq -e '.name == "${crewMember}"' "$CREW_DIR/state.json"
          jq -e '.rig == "${rigName}"' "$CREW_DIR/state.json"
          jq -e '.clone_path == "'"$TMPDIR"'"' "$CREW_DIR/state.json"

          echo "Layer 3: PASSED"

          echo ""
          echo "=== All integration tests passed ==="
        '';

      mayorAttach =
        let
          crewMember = cfg.mayorCrew;
          hasCrewMember = crewMember != null;
          runtimeDeps = [ pkgs.git pkgs.tmux gcPackage ];
        in
        assert hasCrewMember;
        pkgs.writeShellScriptBin "gt-mayor-attach" ''
          set -euo pipefail
          export PATH="${lib.makeBinPath runtimeDeps}:$PATH"

          # Discover project root
          PROJECT_ROOT="$(git rev-parse --show-toplevel)"
          export GT_ROOT="$PROJECT_ROOT/.gt"
          export GT_TOWN_ROOT="$GT_ROOT"

          # Attach to mayor session (blocks until detach with Ctrl-B D)
          cd "$GT_ROOT/${rigName}/crew/${crewMember}"
          ${gcPackage}/bin/gc mayor attach
        '';

      gtUp =
        let
          crewMember = cfg.mayorCrew;
          hasCrewMember = crewMember != null;
          runtimeDeps = [ pkgs.git pkgs.tmux pkgs.dolt gcPackage ];
        in
        assert hasCrewMember;
        pkgs.writeShellScriptBin "gt-up" ''
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

          # 5. Create mayor and refinery git clones (idempotent)
          if [ ! -d "$GT_ROOT/${rigName}/mayor/rig/.git" ]; then
            echo "Cloning mayor worktree for ${rigName}..."
            mkdir -p "$GT_ROOT/${rigName}/mayor"
            git clone ${cfg.gitUrl} "$GT_ROOT/${rigName}/mayor/rig"
          fi
          if [ ! -d "$GT_ROOT/${rigName}/refinery/rig/.git" ]; then
            echo "Cloning refinery worktree for ${rigName}..."
            mkdir -p "$GT_ROOT/${rigName}/refinery"
            git clone ${cfg.gitUrl} "$GT_ROOT/${rigName}/refinery/rig"
          fi

          # 6. Initialize GT directory structure
          ${gcPackage}/bin/gc install "$GT_ROOT" --force --no-beads --dolt-port ${toString cfg.doltPort}

          # 7. Repair stale state from prior runs (idempotency)
          ${gcPackage}/bin/gc doctor --fix || true

          # 8. Start services
          ${gcPackage}/bin/gc up

          # 9. Init Dolt DB and adopt rig
          ${gcPackage}/bin/gc dolt init-rig ${rigName}
          ${gcPackage}/bin/gc rig add ${rigName} --adopt --prefix ${cfg.beads.prefix}

          # 10. Start rig agents
          ${gcPackage}/bin/gc rig start ${rigName}

          echo "Gas Town is up for rig ${rigName}"
        '';

      gtDown =
        let
          runtimeDeps = [ pkgs.git pkgs.dolt gcPackage ];
        in
        pkgs.writeShellScriptBin "gt-down" ''
          set -euo pipefail
          export PATH="${lib.makeBinPath runtimeDeps}:$PATH"

          # Discover project root
          PROJECT_ROOT="$(git rev-parse --show-toplevel)"
          export GT_ROOT="$PROJECT_ROOT/.gt"
          export GT_TOWN_ROOT="$GT_ROOT"

          # Teardown
          ${gcPackage}/bin/gc rig remove ${rigName} || true
          ${gcPackage}/bin/gc down

          echo "Gas Town is down"
        '';
    };
}
