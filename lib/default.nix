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
  # Returns config, JSON file derivations, a combined configDir,
  # and a mayorAttach script that manages the full GT lifecycle.
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

          # 5. Initialize GT directory structure
          ${gtPackage}/bin/gt install "$GT_ROOT" --force --no-beads

          # 6. Ensure gt down runs on exit (detach, signal, error)
          cleanup() { ${gtPackage}/bin/gt down; }
          trap cleanup EXIT

          # 7. Start services (Dolt, daemon, deacon, mayor, witnesses, refineries)
          ${gtPackage}/bin/gt up

          # 8. Attach to mayor session (blocks until detach with Ctrl-B D)
          cd "$CREW_DIR"
          ${gtPackage}/bin/gt mayor attach
          # cleanup runs automatically via trap
        '';

      test =
        let
          testDeps = [
            pkgs.git
            pkgs.jq
            gtPackage
          ];
          crewChecks = concatStringsSep "\n" (
            mapAttrsToList (member: _: ''
              test -f "$GT_ROOT/${rigName}/crew/${member}/config.json" \
                || fail "crew/${member}/config.json missing"
              jq -e '.type == "crew-member"' \
                "$GT_ROOT/${rigName}/crew/${member}/config.json" > /dev/null \
                || fail "crew/${member}/config.json wrong type"
              jq -e --arg name "${member}" '.name == $name' \
                "$GT_ROOT/${rigName}/crew/${member}/config.json" > /dev/null \
                || fail "crew/${member}/config.json wrong name"
              echo "  crew/${member}/config.json: OK"
            '') cfg.crew
          );
          stateCheck = lib.optionalString (cfg.mayorCrew != null) ''
            # Layer 3: Crew state
            echo "=== Layer 3: Crew state ==="
            CREW_DIR="$GT_ROOT/${rigName}/crew/${cfg.mayorCrew}"
            mkdir -p "$CREW_DIR"
            NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            jq -n \
              --arg name "${cfg.mayorCrew}" \
              --arg rig "${rigName}" \
              --arg clone_path "$TEST_DIR" \
              --arg branch "$(git rev-parse --abbrev-ref HEAD)" \
              --arg created_at "$NOW" \
              --arg updated_at "$NOW" \
              '{name: $name, rig: $rig, clone_path: $clone_path, branch: $branch, created_at: $created_at, updated_at: $updated_at}' \
              > "$CREW_DIR/state.json"
            test -f "$CREW_DIR/state.json" || fail "state.json missing"
            jq -e --arg expected "$TEST_DIR" '.clone_path == $expected' \
              "$CREW_DIR/state.json" > /dev/null \
              || fail "state.json clone_path incorrect"
            jq -e --arg name "${rigName}" '.rig == $name' \
              "$CREW_DIR/state.json" > /dev/null \
              || fail "state.json rig incorrect"
            echo "  state.json: OK (clone_path=$TEST_DIR)"
            echo "Layer 3: PASS"
          '';
        in
        pkgs.writeShellScriptBin "gt-test-rig" ''
          set -euo pipefail
          export PATH="${lib.makeBinPath testDeps}:$PATH"

          fail() { echo "FAIL: $1"; exit 1; }

          # Ensure git works in sandboxed environments
          export GIT_AUTHOR_NAME="''${GIT_AUTHOR_NAME:-gt-test}"
          export GIT_AUTHOR_EMAIL="''${GIT_AUTHOR_EMAIL:-test@gt.local}"
          export GIT_COMMITTER_NAME="''${GIT_COMMITTER_NAME:-gt-test}"
          export GIT_COMMITTER_EMAIL="''${GIT_COMMITTER_EMAIL:-test@gt.local}"

          TEST_DIR="$(mktemp -d)"
          trap "rm -rf $TEST_DIR" EXIT
          export HOME="$TEST_DIR"

          cd "$TEST_DIR"
          git init --initial-branch=main
          git commit --allow-empty -m "init"

          export GT_TOWN_ROOT="$TEST_DIR/.gt"
          export GT_ROOT="$GT_TOWN_ROOT"

          # Layer 1: Activation
          echo "=== Layer 1: Activation ==="
          mkdir -p "$GT_ROOT/settings"
          install -m 644 ${rigsJsonFile} "$GT_ROOT/rigs.json"
          install -m 644 ${settingsJsonFile} "$GT_ROOT/settings/config.json"
          mkdir -p "$GT_ROOT/${rigName}"
          install -m 644 ${rigConfigFile} "$GT_ROOT/${rigName}/config.json"
          ${crewActivations}

          test -f "$GT_ROOT/rigs.json" || fail "rigs.json missing"
          jq -e '.version == 1' "$GT_ROOT/rigs.json" > /dev/null \
            || fail "rigs.json wrong version"
          jq -e '.rigs["${rigName}"]' "$GT_ROOT/rigs.json" > /dev/null \
            || fail "rigs.json missing rig entry"
          echo "  rigs.json: OK"

          test -f "$GT_ROOT/settings/config.json" \
            || fail "settings/config.json missing"
          jq -e '.type == "town-settings"' \
            "$GT_ROOT/settings/config.json" > /dev/null \
            || fail "settings/config.json wrong type"
          echo "  settings/config.json: OK"

          test -f "$GT_ROOT/${rigName}/config.json" \
            || fail "${rigName}/config.json missing"
          jq -e '.type == "rig"' \
            "$GT_ROOT/${rigName}/config.json" > /dev/null \
            || fail "${rigName}/config.json wrong type"
          jq -e '.version == 1' \
            "$GT_ROOT/${rigName}/config.json" > /dev/null \
            || fail "${rigName}/config.json wrong version"
          jq -e --arg name "${rigName}" '.name == $name' \
            "$GT_ROOT/${rigName}/config.json" > /dev/null \
            || fail "${rigName}/config.json wrong name"
          echo "  ${rigName}/config.json: OK"

          ${crewChecks}
          echo "Layer 1: PASS"

          # Layer 2: GT workspace discovery
          echo "=== Layer 2: GT workspace discovery ==="
          gt install "$GT_ROOT" --force --no-beads \
            || fail "gt install failed"
          gt rig list || fail "gt rig list failed"
          echo "  gt rig list: OK"
          gt rig config show ${rigName} \
            || fail "gt rig config show failed"
          echo "  gt rig config show ${rigName}: OK"
          echo "Layer 2: PASS"

          ${stateCheck}

          echo ""
          echo "All integration tests passed!"
        '';
    };
}
