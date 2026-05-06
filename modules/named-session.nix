{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    template = mkOption {
      type = types.str;
      description = "Agent name this session is templated from.";
    };

    mode = mkOption {
      type = types.enum [ "always" "on_demand" "never" ];
      default = "always";
      description = "Session lifecycle mode.";
    };

    scope = mkOption {
      type = types.nullOr (types.enum [ "city" "rig" ]);
      default = null;
      description = "Session scope. Omitted from output when null.";
    };
  };
}
