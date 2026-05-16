{ inputs }:

{
  # Build a nixosSystem suitable for running with microvm.nix. The caller passes
  # their own `nixpkgs` (so the consumer flake controls the channel) and the
  # guest `system`; this flake's pinned `microvm` and `llm-agents` are used for
  # the VM runner and packages respectively.
  mkAgentVM =
    { nixpkgs ? inputs.nixpkgs
    , system
    , hostname ? "agent-vm"
    , username ? "agent"
    , uid ? 1000
    , hypervisor ? "qemu"
    , vcpu ? 4
    , mem ? 8192
    , shares ? [ ]
    , volumes ? null
    , interfaces ? null
    , extraPackages ? [ ]
    , extraModules ? [ ]
    }:
    nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        llmAgents = inputs.llm-agents.packages.${system};
      };
      modules = [
        inputs.microvm.nixosModules.microvm
        (import ../modules/agent-vm.nix)
        ({ lib, ... }: {
          agentVm = {
            enable = true;
            inherit hostname username uid extraPackages;
          };
          microvm = {
            inherit hypervisor vcpu mem;
          } // (if shares == [ ] then { } else { inherit shares; })
            // (lib.optionalAttrs (volumes != null) { inherit volumes; })
            // (lib.optionalAttrs (interfaces != null) { inherit interfaces; });
        })
      ] ++ extraModules;
    };

  # Convenience: build a virtiofs share entry. Use this when composing the
  # `shares` list passed to mkAgentVM.
  mkShare =
    { source
    , mountPoint
    , tag ? null
    , proto ? "virtiofs"
    }:
    {
      inherit source mountPoint proto;
      tag = if tag != null then tag
            else builtins.substring 0 20 (builtins.hashString "sha256" mountPoint);
    };
}
