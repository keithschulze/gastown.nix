{ config, lib, pkgs, llmAgents, ... }:

let
  cfg = config.agentVm;
in
{
  options.agentVm = {
    enable = lib.mkEnableOption "Claude Code + beads agent microVM defaults";

    username = lib.mkOption {
      type = lib.types.str;
      default = "agent";
      description = ''
        Primary user account inside the VM. For host-path shares to be writable
        by this user, set `uid` to match the owning UID on the host.
      '';
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "UID/GID for the primary user.";
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "agent-vm";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra system packages installed inside the VM.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.hostName = cfg.hostname;
    system.stateVersion = lib.mkDefault "25.11";

    users.mutableUsers = false;
    users.groups.${cfg.username}.gid = cfg.uid;
    users.users.${cfg.username} = {
      isNormalUser = true;
      uid = cfg.uid;
      group = cfg.username;
      home = "/home/${cfg.username}";
      shell = pkgs.zsh;
      initialPassword = "agent";
      extraGroups = [ "wheel" ];
    };

    security.sudo.wheelNeedsPassword = false;

    programs.zsh.enable = true;
    services.getty.autologinUser = cfg.username;

    environment.systemPackages = (with pkgs; [
      git
      gnupg
      openssh
      jq
      ripgrep
      fzf
      htop
      lsof
      helix
    ]) ++ [
      llmAgents.claude-code
      llmAgents.beads-rust
    ] ++ cfg.extraPackages;

    environment.sessionVariables = {
      CLAUDE_CONFIG_DIR = "/home/${cfg.username}/.claude";
    };

    programs.ssh.startAgent = true;
    programs.gnupg.agent.enable = true;

    microvm = {
      hypervisor = lib.mkDefault "qemu";
      vcpu = lib.mkDefault 4;
      mem = lib.mkDefault 8192;
      writableStoreOverlay = lib.mkDefault "/nix/.rw-store";

      volumes = lib.mkDefault [{
        image = "nix-store-overlay.img";
        mountPoint = "/nix/.rw-store";
        size = 16384;
      }];

      # Always-on virtiofs share of the host /nix/store. User-defined shares
      # in additional modules append to this list rather than replacing it.
      shares = [{
        proto = "virtiofs";
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
      }];

      interfaces = lib.mkDefault [{
        type = "user";
        id = "usernet";
        mac = "02:00:00:01:01:01";
      }];
    };

    networking.useDHCP = lib.mkDefault false;
    networking.interfaces.eth0.useDHCP = lib.mkDefault true;
    networking.firewall.enable = lib.mkDefault false;

    nix = {
      settings = {
        experimental-features = [ "nix-command" "flakes" ];
        sandbox = false;
        build-dir = "/nix/.rw-store/nix-build";
        trusted-users = [ "root" cfg.username ];
        substituters = [
          "https://cache.nixos.org"
          "https://cache.numtide.com"
          "https://microvm.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
          "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys="
        ];
      };
    };

    systemd.tmpfiles.rules = [
      "d /nix/.rw-store/nix-build 0755 root root -"
    ];
  };
}
