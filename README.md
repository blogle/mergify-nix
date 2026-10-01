# mergify-nix

A small Nix flake that packages [Mergify CLI](https://github.com/Mergifyio/mergify-cli) and exposes an `installSkills` hook for keeping Mergify's upstream agent skills current in downstream projects.

## Use the CLI in a downstream flake

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

The CLI package is pinned through your downstream `flake.lock` like any other flake input.

## `installSkills`

Calling:

```nix
shellHook = ''
  ${mergify-nix.lib.installSkills system}
'';
```

runs the packaged `install-mergify-skills` helper whenever the dev shell starts.

The helper:

- fetches the latest `main` branch of `Mergifyio/mergify-cli` at execution time;
- installs every upstream directory under `skills/` into `.agent/skills/`;
- updates existing Mergify-managed skills in place;
- removes Mergify-managed skills that were removed upstream;
- preserves unrelated project and third-party skills;
- uses the Git repository root when available, falling back to the current directory.

Set `MERGIFY_SKILLS_DIR` to override the destination:

```bash
MERGIFY_SKILLS_DIR="$PWD/.custom/skills" install-mergify-skills
```

You can also run the updater directly:

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

Downstream projects control the packaged CLI revision through their lockfile:

```bash
nix flake update mergify-nix
```

The skills hook is intentionally different: it resolves upstream `main` each time it is run so skills stay current without waiting for a flake-input update.
