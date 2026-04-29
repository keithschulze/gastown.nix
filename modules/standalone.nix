{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  crewNames = builtins.attrNames config.crew;
  crewCount = builtins.length crewNames;
in
{
  imports = [ ./rig.nix ];

  options = {
    name = mkOption {
      type = types.str;
      description = "Rig name, used as the directory under GT_ROOT.";
    };

    mayorCrew = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Which crew member mayorAttach uses. When null and exactly one crew
        member is declared, that member is auto-selected.
      '';
    };

    defaultAgent = mkOption {
      type = types.str;
      default = "claude";
      description = "Default agent type for the rig.";
    };
  };

  config = lib.mkIf (crewCount == 1) {
    mayorCrew = lib.mkDefault (builtins.head crewNames);
  };
}
