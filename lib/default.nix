{ lib }:
let
  inherit (lib)
    evalModules
    filter
    mapAttrs
    mapAttrsToList
    optionalAttrs
    recursiveUpdate
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

  # Convert one evaluated agent into the [[agent]] entry that goes into pack.toml.
  # Returns null when promptTemplate is null (agent comes from an imported pack).
  agentToPackEntry =
    name: a:
    if a.promptTemplate == null then
      null
    else
      {
        inherit name;
        prompt_template = "agents/${name}/prompt.template.md";
      };

  # Convert one evaluated agent into its agent.toml attrset, or null if no overrides set.
  agentToAgentToml =
    a:
    let
      base = (
        optionalAttrs (a.dir != null) { inherit (a) dir; }
        // optionalAttrs (a.provider != null) { inherit (a) provider; }
        // optionalAttrs (a.optionDefaults != { }) { option_defaults = a.optionDefaults; }
      );
      merged = recursiveUpdate base a.extraAgentToml;
    in
    if merged == { } then null else merged;

  namedSessionToValue =
    s:
    { inherit (s) template mode; } // optionalAttrs (s.scope != null) { inherit (s) scope; };

  packToValue =
    cfg:
    let
      agentEntries = filter (e: e != null) (mapAttrsToList agentToPackEntry cfg.agents);
      sessionEntries = map namedSessionToValue cfg.namedSessions;
      base = {
        pack = {
          inherit (cfg) name schema;
        };
      } // optionalAttrs (agentEntries != [ ]) { agent = agentEntries; }
        // optionalAttrs (sessionEntries != [ ]) { named_session = sessionEntries; };
    in
    recursiveUpdate base cfg.extraPackToml;

  cityToValue =
    cfg:
    let
      base = {
        workspace = { inherit (cfg.workspace) provider; };
      } // optionalAttrs (cfg.rigs != [ ]) {
        rigs = map (name: { inherit name; }) cfg.rigs;
      };
    in
    recursiveUpdate base cfg.extraCityToml;
in
{
  # Pure evaluation of a pack module. No pkgs required.
  evalPack =
    {
      modules ? [ ],
      config ? { },
    }:
    doEvalPack ([ { inherit config; } ] ++ modules);

  # Pure evaluation of a city module. No pkgs required.
  evalCity =
    {
      modules ? [ ],
      config ? { },
    }:
    doEvalCity ([ { inherit config; } ] ++ modules);

  # Build a pack tree: a directory containing pack.toml plus agents/<name>/
  # subtrees with prompt.template.md and optional agent.toml.
  mkPack =
    {
      pkgs,
      modules ? [ ],
      config ? { },
    }:
    let
      cfg = doEvalPack ([ { inherit config; } ] ++ modules);
      fmt = pkgs.formats.toml { };

      packToml = fmt.generate "${cfg.name}-pack.toml" (packToValue cfg);

      # An agent contributes files when it has a prompt template and/or
      # agent.toml overrides. A pure-overrides agent (no promptTemplate) emits
      # only agent.toml — useful for tweaking an agent inherited from an
      # imported system pack.
      mkAgentDir =
        name: a:
        let
          promptFile =
            if a.promptTemplate == null then
              null
            else if builtins.isPath a.promptTemplate then
              a.promptTemplate
            else
              pkgs.writeText "${name}-prompt.template.md" a.promptTemplate;

          agentToml = agentToAgentToml a;
          agentTomlFile =
            if agentToml == null then
              null
            else
              fmt.generate "${name}-agent.toml" agentToml;

          installPrompt =
            if promptFile == null then
              ""
            else
              "install -m 644 ${promptFile} $out/agents/${name}/prompt.template.md";

          installAgentToml =
            if agentTomlFile == null then
              ""
            else
              "install -m 644 ${agentTomlFile} $out/agents/${name}/agent.toml";
        in
        if promptFile == null && agentTomlFile == null then
          null
        else
          pkgs.runCommand "${cfg.name}-agent-${name}" { } ''
            mkdir -p $out/agents/${name}
            ${installPrompt}
            ${installAgentToml}
          '';

      agentDirs = lib.filter (d: d != null) (mapAttrsToList mkAgentDir cfg.agents);
    in
    pkgs.runCommand "${cfg.name}-pack" { } ''
      mkdir -p $out
      install -m 644 ${packToml} $out/pack.toml
      ${lib.concatMapStringsSep "\n" (d: "cp -r --no-preserve=mode ${d}/. $out/") agentDirs}
    '';

  # Build a city tree: pack tree merged with city.toml.
  mkCity =
    {
      pkgs,
      pack,
      modules ? [ ],
      config ? { },
    }:
    let
      cfg = doEvalCity ([ { inherit config; } ] ++ modules);
      fmt = pkgs.formats.toml { };

      cityToml = fmt.generate "city.toml" (cityToValue cfg);

      tree = pkgs.runCommand "city-tree" { } ''
        mkdir -p $out
        cp -r --no-preserve=mode ${pack}/. $out/
        install -m 644 ${cityToml} $out/city.toml
      '';
    in
    {
      config = cfg;
      inherit cityToml pack tree;
    };
}
