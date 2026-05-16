{
  description = "My isolated Claude Code workstation";

  nixConfig = {
    extra-substituters = [
      "https://cache.numtide.com"
      "https://microvm.cachix.org"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    agent-vm = {
      url = "github:keithschulze/agent-vm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, agent-vm }:
    let
      # The host I run this on (set to "aarch64-darwin" for Apple Silicon Macs).
      hostSystem = "aarch64-darwin";

      # Guests are always Linux. Use the matching arch for your host.
      guestSystem = "aarch64-linux";

      # EDIT THESE: absolute host paths to mount into the VM.
      homeOnHost      = "/Users/me";
      workspaceOnHost = "${homeOnHost}/workspace/my-project";
      sshOnHost       = "${homeOnHost}/.ssh";
      gnupgOnHost     = "${homeOnHost}/.gnupg";
      claudeOnHost    = "${homeOnHost}/.claude";
      beadsOnHost     = "${workspaceOnHost}/.beads";

      username = "me";

      vm = agent-vm.lib.mkAgentVM {
        inherit nixpkgs;
        system = guestSystem;
        hostname = "claude-vm";
        inherit username;
        hypervisor = "vfkit";     # macOS host. Use "qemu" on Linux.
        vcpu = 4;
        mem = 8192;

        shares = [
          {
            proto = "virtiofs";
            tag = "workspace";
            source = workspaceOnHost;
            mountPoint = "/home/${username}/workspace";
          }
          {
            proto = "virtiofs";
            tag = "ssh-keys";
            source = sshOnHost;
            mountPoint = "/home/${username}/.ssh";
          }
          {
            proto = "virtiofs";
            tag = "claude-config";
            source = claudeOnHost;
            mountPoint = "/home/${username}/.claude";
          }
          {
            proto = "virtiofs";
            tag = "beads";
            source = beadsOnHost;
            mountPoint = "/home/${username}/.beads";
          }
          # GPG: share the whole ~/.gnupg dir so `gpg --sign` works inside
          # the VM using host-resident keys. Note that the agent socket inside
          # this directory is unlikely to function over virtiofs — gpg will
          # spawn its own in-VM agent and load keys from the shared keyring.
          {
            proto = "virtiofs";
            tag = "gnupg";
            source = gnupgOnHost;
            mountPoint = "/home/${username}/.gnupg";
          }
        ];

        # Add per-user packages here, or push more involved customisation
        # (home-manager, dotfiles) into extraModules.
        extraPackages = [ ];

        extraModules = [
          # Example: pin git identity for in-VM commits.
          ({ ... }: {
            environment.etc."gitconfig".text = ''
              [user]
                name = Your Name
                email = you@example.com
              [init]
                defaultBranch = main
              [pull]
                rebase = true
            '';
          })
        ];
      };
    in
    {
      packages.${hostSystem}.default = vm.config.microvm.declaredRunner;
      nixosConfigurations.claude-vm = vm;
    };
}
