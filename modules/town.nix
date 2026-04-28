{ config, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    settings = {
      defaultAgent = mkOption {
        type = types.str;
        default = "claude";
        description = "Default agent type for the town.";
      };
    };

    rigs = mkOption {
      type = types.attrsOf (types.submodule ./rig.nix);
      default = { };
      description = "Rig definitions for the town.";
    };
  };
}
