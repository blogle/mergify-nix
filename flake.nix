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

          mergifyRev = mergify-cli.rev;

          rustToolchain =
            pkgs.rust-bin.fromRustupToolchainFile
              (mergify-cli + "/rust-toolchain.toml");

          rustPlatform = pkgs.makeRustPlatform {
            cargo = rustToolchain;
            rustc = rustToolchain;
          };

          mergify = rustPlatform.buildRustPackage {
            pname = "mergify-cli";
            version = "unstable-${builtins.substring 0 7 mergifyRev}";

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
            runtimeInputs = [
              pkgs.git
              pkgs.nodejs
            ];

            text = ''
              root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              cd "$root"

              npx --yes skills add \
                "Mergifyio/mergify-cli#${mergifyRev}" \
                --skill '*' \
                --agent universal \
                --yes
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
