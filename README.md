# agent-vm.nix

Run Claude Code (and friends) inside an isolated NixOS microVM. The flake
glues together [`microvm.nix`][microvm] and [`llm-agents.nix`][llm-agents]:
the former gives you a declarative VM runner that works on Linux and macOS
(via vfkit), the latter ships pre-built `claude-code`, `beads-rust`, `codex`,
etc. from a binary cache so you don't compile them yourself.

> **Status**: foundation only. Boots a VM with Claude + beads on the PATH,
> auto-logs in, and lets you mount host directories (workspace, ssh, gnupg,
> beads DB, …) via virtiofs. Home-manager is intentionally not bundled — plug
> in your own via `extraModules`.

[microvm]: https://github.com/microvm-nix/microvm.nix
[llm-agents]: https://github.com/numtide/llm-agents.nix

## Quickstart (dogfood VM)

The flake exposes a self-contained VM with no host mounts, useful for
checking everything resolves:

```sh
nix run github:keithschulze/agent-vm.nix#vm
```

On first run microvm.nix creates a writable nix-store overlay image in the
current working directory and boots the guest. Log in is automatic
(`agent` / `agent`).

## Using it in your own flake

```sh
nix flake init -t github:keithschulze/agent-vm.nix
```

That drops a `flake.nix` you edit to set `username`, the host paths to mount,
and the hypervisor (`vfkit` on macOS, `qemu` on Linux). Then:

```sh
nix run .#default
```

A minimal example:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agent-vm = {
      url = "github:keithschulze/agent-vm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, agent-vm }:
    let
      vm = agent-vm.lib.mkAgentVM {
        inherit nixpkgs;
        system     = "aarch64-linux";   # guest arch
        hypervisor = "vfkit";           # macOS host; use "qemu" on Linux
        username   = "me";
        shares = [
          { proto = "virtiofs"; tag = "ws";     source = "/Users/me/workspace"; mountPoint = "/home/me/workspace"; }
          { proto = "virtiofs"; tag = "ssh";    source = "/Users/me/.ssh";      mountPoint = "/home/me/.ssh"; }
          { proto = "virtiofs"; tag = "claude"; source = "/Users/me/.claude";   mountPoint = "/home/me/.claude"; }
          { proto = "virtiofs"; tag = "beads";  source = "/Users/me/workspace/proj/.beads"; mountPoint = "/home/me/.beads"; }
          { proto = "virtiofs"; tag = "gnupg";  source = "/Users/me/.gnupg";    mountPoint = "/home/me/.gnupg"; }
        ];
      };
    in {
      packages.aarch64-darwin.default = vm.config.microvm.declaredRunner;
    };
}
```

## `mkAgentVM` parameters

| Parameter       | Type                          | Default            | Notes |
|-----------------|-------------------------------|--------------------|-------|
| `nixpkgs`       | flake input                   | this flake's       | Caller-supplied nixpkgs; used to call `lib.nixosSystem`. |
| `system`        | string                        | *required*         | Guest system (always Linux, e.g. `aarch64-linux`). |
| `hostname`      | string                        | `"agent-vm"`       | VM hostname. |
| `username`      | string                        | `"agent"`          | Primary user account. |
| `uid`           | int                           | `1000`             | Match this to your host UID for write access to shared dirs. |
| `hypervisor`    | string                        | `"qemu"`           | `"vfkit"` on macOS. |
| `vcpu`          | int                           | `4`                | |
| `mem`           | int (MiB)                     | `8192`             | |
| `shares`        | list of microvm share attrs   | `[ ]`              | Appended to the mandatory ro-store share. Each entry is `{ proto, tag, source, mountPoint }`. |
| `volumes`       | list / `null`                 | `null`             | Override the default writable-store overlay volume. |
| `interfaces`    | list / `null`                 | `null`             | Override the default user-mode network interface. |
| `extraPackages` | list of packages              | `[ ]`              | Added to `environment.systemPackages` inside the VM. |
| `extraModules`  | list of NixOS modules         | `[ ]`              | Drop in your home-manager config, git identity, etc. here. |

`mkAgentVM` returns a full `nixosSystem`; reach `vm.config.microvm.declaredRunner`
for the runnable derivation.

## What ships inside the VM

- `claude-code`, `beads-rust` from `llm-agents.nix`
- `git`, `gnupg`, `openssh`
- `jq`, `ripgrep`, `fzf`, `htop`, `lsof`, `helix`
- zsh as the login shell
- auto-login on tty for `username`
- nix configured for flakes, with the numtide + microvm caches trusted

Everything else (home-manager, dotfiles, tmux, direnv, helix config, …) is up
to you to compose into `extraModules`.

## Host requirements

- **Linux host**: `nix` with flakes enabled. The default `qemu` hypervisor is
  picked up from nixpkgs at runtime.
- **macOS host**: a working `nix-darwin`/`nix` install **plus** a Linux remote
  builder. microvm.nix can run the VM via vfkit on macOS, but the guest
  derivation itself has to be built on Linux. See microvm.nix's FAQ for the
  `linux-builder` setup.

The flake declares both `cache.numtide.com` (for `claude-code`, `beads-rust`,
…) and `microvm.cachix.org` (for the runner). Accept them with
`--accept-flake-config` the first time.

## Sharing GPG / SSH keys with the host

There are two patterns, both with tradeoffs:

1. **Share the directory** — mount `~/.gnupg` (or `~/.ssh`) into the VM. The
   private keys live on the host disk and are visible inside the guest via
   virtiofs. gpg will spawn its own agent inside the guest. Unix-socket
   forwarding (the host's `gpg-agent` socket inside the shared dir) is not
   reliable over virtiofs, so don't count on agent-mediated signing — count
   on the keyring being readable. Pros: simple. Cons: private key material
   is now reachable from inside the (otherwise isolated) VM.

2. **Forward the agent socket** — run `socat` (or similar) on the host to
   bridge the host agent socket to a TCP port, then connect from inside the
   guest. More setup; keeps keys off the guest. Not wired up by this flake.

If you only need git commit signing, option 1 is the path of least
resistance: share `~/.gnupg`, let gpg-agent run inside the VM, type your
passphrase once per session.

## What this flake does *not* do

- Doesn't provision your dotfiles or shell config — bring your own
  `home-manager` module via `extraModules`.
- Doesn't manage credentials, agents, or secret storage on the host.
- Doesn't enforce any specific work-tracking workflow — `beads-rust` is on
  the PATH; pointing it at a shared `.beads/` directory is your call.
