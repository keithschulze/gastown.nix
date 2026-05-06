{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    workspace = {
      provider = mkOption {
        type = types.str;
        default = "claude";
        description = ''
          Coding-agent provider for this city (e.g. `claude`, `codex`,
          `gemini`). This is the per-workspace default; individual agents
          can override via their own `provider` option.
        '';
      };
    };

    rigs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Rig names declared by this city. Each becomes a `[[rigs]]` block
        with `name = "<rig>"`. Filesystem path bindings live in the
        machine-local `.gc/site.toml` (managed by `gc rig add`), not here.
      '';
      example = [ "gt_nix" "wyvern" ];
    };

    extraCityToml = mkOption {
      type = types.attrs;
      default = { };
      description = "Escape hatch for `city.toml` fields not modelled here.";
    };
  };
}
