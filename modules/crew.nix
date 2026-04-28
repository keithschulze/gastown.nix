{ config, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    role = mkOption {
      type = types.str;
      default = "developer";
      description = "Role of the crew member (e.g. developer, reviewer, lead).";
    };

    githubUsername = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "GitHub username for the crew member.";
    };

    email = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Email address for the crew member.";
    };
  };
}
