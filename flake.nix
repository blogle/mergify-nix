{
  description = "Nix packaging for Mergify CLI with an installSkills hook";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mergify-cli = {
      url = "github:Mergifyio/mergify-cli";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      mergify-cli,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };

          rustToolchain =
            pkgs.rust-bin.fromRustupToolchainFile
              (mergify-cli + "/rust-toolchain.toml");

          rustPlatform = pkgs.makeRustPlatform {
            cargo = rustToolchain;
            rustc = rustToolchain;
          };

          mergify = rustPlatform.buildRustPackage {
            pname = "mergify-cli";
            version = "unstable";

            src = mergify-cli;

            cargoLock = {
              lockFile = mergify-cli + "/Cargo.lock";
            };

            cargoBuildFlags = [
              "-p"
              "mergify-cli"
            ];

            # Upstream's test suite is intentionally not part of this packaging
            # derivation. This flake packages the upstream CLI as-is.
            doCheck = false;

            meta = {
              description = "Mergify command-line interface";
              homepage = "https://github.com/Mergifyio/mergify-cli";
              license = pkgs.lib.licenses.asl20;
              mainProgram = "mergify";
            };
          };

          installSkills = pkgs.writeShellApplication {
            name = "install-mergify-skills";

            runtimeInputs = with pkgs; [
              coreutils
              curl
              findutils
              git
              gnugrep
              gnutar
              gzip
            ];

            text = ''
              set -euo pipefail

              if [[ -n "''${MERGIFY_SKILLS_DIR:-}" ]]; then
                destination="$MERGIFY_SKILLS_DIR"
              elif project_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
                destination="$project_root/.agent/skills"
              else
                destination="$PWD/.agent/skills"
              fi

              mkdir -p "$destination"

              tmp="$(mktemp -d)"
              trap 'rm -rf "$tmp"' EXIT

              archive="$tmp/mergify-cli.tar.gz"

              # Deliberately fetch main at hook execution time rather than using
              # the flake-locked source so downstream projects always receive
              # the latest published Mergify skills.
              curl \
                --fail \
                --silent \
                --show-error \
                --location \
                --retry 3 \
                --output "$archive" \
                "https://codeload.github.com/Mergifyio/mergify-cli/tar.gz/refs/heads/main"

              tar -xzf "$archive" -C "$tmp"

              source_root="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -print -quit)"
              source_skills="$source_root/skills"

              if [[ ! -d "$source_skills" ]]; then
                echo "Mergify skills directory not found in upstream archive" >&2
                exit 1
              fi

              manifest="$destination/.mergify-cli-managed"
              next_manifest="$tmp/managed-skills"

              # Remove only skills previously managed by this hook. This keeps
              # project-local and other third-party skills untouched.
              if [[ -f "$manifest" ]]; then
                while IFS= read -r skill_name; do
                  [[ -n "$skill_name" ]] || continue
                  if [[ "$skill_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
                    rm -rf "$destination/$skill_name"
                  fi
                done < "$manifest"
              fi

              : > "$next_manifest"

              while IFS= read -r -d "" skill_dir; do
                skill_name="$(basename "$skill_dir")"
                rm -rf "$destination/$skill_name"
                cp -a "$skill_dir" "$destination/$skill_name"
                printf '%s\n' "$skill_name" >> "$next_manifest"
              done < <(
                find "$source_skills" \
                  -mindepth 1 \
                  -maxdepth 1 \
                  -type d \
                  -print0
              )

              sort -o "$next_manifest" "$next_manifest"
              cp "$next_manifest" "$manifest"

              echo "Updated Mergify skills in $destination"
            '';
          };
        in
        {
          default = mergify;
          mergify-cli = mergify;
          installSkills = installSkills;
        }
      );

      apps = forAllSystems (
        system:
        {
          default = {
            type = "app";
            program = "${self.packages.${system}.mergify-cli}/bin/mergify";
          };

          installSkills = {
            type = "app";
            program = "${self.packages.${system}.installSkills}/bin/install-mergify-skills";
          };
        }
      );

      lib.installSkills =
        system:
        "${self.packages.${system}.installSkills}/bin/install-mergify-skills";
    };
}
