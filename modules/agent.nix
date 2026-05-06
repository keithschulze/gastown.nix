{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    promptTemplate = mkOption {
      type = types.nullOr (types.either types.path types.lines);
      default = null;
      description = ''
        Prompt template for the agent. May be a path to a `.md` file or an
        inline markdown string. When non-null, the agent is emitted as an
        `[[agent]]` entry in `pack.toml` and the template is materialised at
        `agents/<name>/prompt.template.md`. When null, no `[[agent]]` block is
        emitted (use this when the agent comes from an imported system pack
        and you only want to set per-agent overrides).
      '';
    };

    dir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Working directory override (`dir = ...` in `agent.toml`).";
    };

    provider = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Coding-agent provider override (e.g. `claude`, `codex`).";
    };

    optionDefaults = mkOption {
      type = types.attrsOf (types.oneOf [ types.str types.bool types.int ]);
      default = { };
      description = "Provider option defaults (`option_defaults = { ... }` in `agent.toml`).";
      example = {
        model = "sonnet";
        permission_mode = "plan";
      };
    };

    extraAgentToml = mkOption {
      type = types.attrs;
      default = { };
      description = ''
        Escape hatch for `agent.toml` fields not modelled here (e.g.
        `wake_mode`, `nudge`, `idle_timeout`, `pre_start`, `work_dir`,
        `max_active_sessions`). Merged into the generated `agent.toml`.
      '';
    };
  };
}
