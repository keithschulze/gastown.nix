{ config, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    name = mkOption {
      type = types.str;
      description = "Pack name, used to identify this agent pack.";
    };

    schema = mkOption {
      type = types.int;
      default = 2;
      description = "Schema version for the pack definition.";
    };

    agents = mkOption {
      type = types.attrsOf (types.submodule ./agent.nix);
      default = { };
      description = "Agent definitions for this pack.";
      example = {
        mayor = {
          scope = "town";
          provider = "claude";
          maxConcurrent = 1;
        };
        witness = {
          scope = "rig";
          provider = "claude";
          maxConcurrent = 1;
        };
        polecat = {
          scope = "rig";
          provider = "claude";
          maxConcurrent = 10;
        };
      };
    };
  };
}
