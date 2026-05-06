{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    name = mkOption {
      type = types.str;
      description = "Pack name (`pack.name`).";
    };

    schema = mkOption {
      type = types.int;
      default = 2;
      description = "Pack schema version (`pack.schema`).";
    };

    agents = mkOption {
      type = types.attrsOf (types.submodule ./agent.nix);
      default = { };
      description = ''
        Agent definitions for this pack. Each entry produces an `[[agent]]`
        block in `pack.toml` (when `promptTemplate` is set) and an optional
        `agents/<name>/agent.toml` for overrides.
      '';
      example = {
        mayor.promptTemplate = "# Mayor\n...";
      };
    };

    namedSessions = mkOption {
      type = types.listOf (types.submodule ./named-session.nix);
      default = [ ];
      description = "Named sessions emitted as `[[named_session]]` blocks.";
      example = [
        { template = "mayor"; mode = "always"; scope = "city"; }
      ];
    };

    extraPackToml = mkOption {
      type = types.attrs;
      default = { };
      description = ''
        Escape hatch for `pack.toml` sections not modelled here (e.g.
        `[imports.*]`, `[global]`, `[[patches.agent]]`). Merged into the
        generated `pack.toml`.
      '';
    };
  };
}
