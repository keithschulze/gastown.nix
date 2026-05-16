{
  description = "Run Claude Code and beads inside an isolated NixOS microVM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, microvm, llm-agents }:
    let
      hostSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      forAllHosts = nixpkgs.lib.genAttrs hostSystems;

      # Guests are always Linux; map a host system to its matching guest arch.
      guestOf = {
        "aarch64-darwin" = "aarch64-linux";
        "aarch64-linux"  = "aarch64-linux";
        "x86_64-darwin"  = "x86_64-linux";
        "x86_64-linux"   = "x86_64-linux";
      };

      agentLib = import ./lib { inherit inputs; };

      # Dogfood VM used by `nix run .#vm` so this repo is testable on its own.
      mkDogfood = hostSystem:
        agentLib.mkAgentVM {
          system = guestOf.${hostSystem};
          hostname = "agent-vm";
          username = "agent";
          # No shares beyond the mandatory ro-store — the dogfood VM is
          # self-contained. Real users mount $HOME paths via the templates.
        };
    in
    {
      lib = agentLib;

      nixosModules = {
        default = import ./modules/agent-vm.nix;
        agent-vm = import ./modules/agent-vm.nix;
      };

      packages = forAllHosts (hostSystem:
        let vm = mkDogfood hostSystem; in {
          default = vm.config.microvm.declaredRunner;
          vm = vm.config.microvm.declaredRunner;
        });

      templates.default = {
        path = ./templates/default;
        description = "Example flake consuming agent-vm.nix with host mounts.";
      };

      # Exposed so external tools can refer to the dogfood guest config.
      nixosConfigurations.dogfood = mkDogfood "x86_64-linux";
    };
}
