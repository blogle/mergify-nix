# mergify-nix

A small Nix flake that packages [Mergify CLI](https://github.com/Mergifyio/mergify-cli) and exposes an `installSkills` hook for installing Mergify's AI agent skills into downstream projects.

Both the CLI and the skills are pinned to the same upstream Mergify commit by the flake lock.

## Use in a downstream flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    mergify-nix.url = "github:blogle/mergify-nix";
  };

  outputs = { nixpkgs, mergify-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          mergify-nix.packages.${system}.default
        ];

        shellHook = ''
          ${mergify-nix.lib.installSkills system}
        '';
      };
    };
}
```

## `installSkills`

The hook delegates skill installation to the standard [skills](https://skills.sh/) CLI recommended by Mergify:

```bash
npx skills add Mergifyio/mergify-cli
```

Rather than following upstream `main` independently, `mergify-nix` adds the exact commit referenced by the `mergify-cli` flake input:

```text
Mergifyio/mergify-cli#<locked-revision>
```

It installs every Mergify skill for the universal agent target, whose project path is `.agents/skills/`. The hook runs from the Git repository root so entering a dev shell from a subdirectory still updates the project-level skills.

You can also run it directly:

```bash
nix run github:blogle/mergify-nix#installSkills
```

## Run Mergify directly

```bash
nix run github:blogle/mergify-nix
```

## Supported systems

- `x86_64-linux`
- `aarch64-linux`
- `x86_64-darwin`
- `aarch64-darwin`

## Updating

Update the flake input in a downstream project:

```bash
nix flake update mergify-nix
```

That advances the packaged Mergify CLI and the revision used by `installSkills` together.
