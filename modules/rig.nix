{ config, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    gitUrl = mkOption {
      type = types.str;
      description = "Git URL for the rig's repository.";
    };

    defaultBranch = mkOption {
      type = types.str;
      default = "main";
      description = "Default branch name.";
    };

    beads = {
      prefix = mkOption {
        type = types.str;
        description = "Issue ID prefix for this rig (e.g. 'gn' for gt_nix).";
      };
    };

    maxPolecats = mkOption {
      type = types.ints.positive;
      default = 10;
      description = "Maximum number of concurrent polecat workers.";
    };

    autoRestart = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically restart agents on failure.";
    };

    autoStartOnUp = mkOption {
      type = types.bool;
      default = false;
      description = "Start agents automatically when the rig comes up.";
    };

    defaultFormula = mkOption {
      type = types.str;
      default = "mol-polecat-work";
      description = "Default workflow formula for polecats.";
    };

    dnd = mkOption {
      type = types.bool;
      default = false;
      description = "Do Not Disturb mode for notifications.";
    };

    polecatBranchTemplate = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Custom branch naming template for polecats.";
    };

    priorityAdjustment = mkOption {
      type = types.int;
      default = 0;
      description = "Priority offset for work dispatch.";
    };

    crew = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of crew member names.";
      example = [ "alice" "bob" ];
    };
  };
}
