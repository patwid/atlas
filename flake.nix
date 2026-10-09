{
  description = "Atlas: Gleam + Lustre frontend on PocketBase (package, app and development shell)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Everything the packages and the checks share, per system.
      atlasFor = pkgs:
        let
          lib = pkgs.lib;
          source = fileset: lib.fileset.toSource { root = ./.; inherit fileset; };

          # Hex packages for the offline build. Gleam keeps downloads in a cache whose file
          # names are the packages' checksums, and manifest.toml records exactly those.
          manifest = builtins.fromTOML (builtins.readFile ./frontend/manifest.toml);
          hexPackages = pkgs.linkFarm "atlas-hex-packages" (map
            (p: {
              name = "${p.outer_checksum}.tar";
              path = pkgs.fetchurl {
                url = "https://repo.hex.pm/tarballs/${p.name}-${p.version}.tar";
                sha256 = lib.toLower p.outer_checksum;
              };
            })
            manifest.packages);

          # Shell lines that give a build Gleam's download cache filled from hexPackages.
          useHexPackages = ''
            export HOME=$TMPDIR/home
            mkdir -p $HOME/.cache/gleam/hex/hexpm
            cp -rL ${hexPackages} $HOME/.cache/gleam/hex/hexpm/packages
            chmod -R u+w $HOME
          '';

          # The Bun that lustre_dev_tools would download cannot run in the build sandbox.
          useSystemBun = ''
            printf '\n[tools.lustre.bin]\nbun = "system"\n' >> frontend/gleam.toml
          '';

          buildId = "${self.shortRev or self.dirtyShortRev or "dev"}-${self.lastModifiedDate or "0"}";

          # The built app: the static frontend plus the PocketBase hooks and migrations.
          # The source leaves out the tests, so unrelated edits do not rebuild the app.
          atlas-app = pkgs.stdenvNoCC.mkDerivation {
            pname = "atlas-app";
            version = "0-${buildId}";
            src = source (lib.fileset.difference
              (lib.fileset.unions [ ./frontend ./backend ./scripts/build-frontend.sh ])
              (lib.fileset.unions [ ./frontend/test ./frontend/test-js ./backend/tests ]));
            nativeBuildInputs = with pkgs; [ gleam beam27Packages.erlang beam27Packages.rebar3 bun git ];

            buildPhase = ''
              runHook preBuild
              ${useHexPackages}
              ${useSystemBun}
              ATLAS_BUILD_ID=${buildId} ATLAS_PUBLIC_OUT=$PWD/pb_public \
                bash scripts/build-frontend.sh
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out/share/atlas
              cp -r pb_public $out/share/atlas/pb_public
              cp -r backend/pb_hooks backend/pb_migrations $out/share/atlas/
              runHook postInstall
            '';
          };

          # Starts PocketBase on the built app. Data lives outside the store.
          atlas = pkgs.writeShellApplication {
            name = "atlas";
            runtimeInputs = [ pkgs.pocketbase ];
            text = ''
              data="''${ATLAS_DATA_DIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/atlas}"
              mkdir -p "$data"
              echo "atlas: data in $data" >&2
              exec pocketbase serve \
                --dir "$data/pb_data" \
                --hooksDir ${atlas-app}/share/atlas/pb_hooks \
                --migrationsDir ${atlas-app}/share/atlas/pb_migrations \
                --publicDir ${atlas-app}/share/atlas/pb_public \
                --hooksWatch=false --automigrate=false \
                "$@"
            '';
          };

          # A test suite as a derivation (ADR 0042): it builds only if the tests pass, and is not run
          # again until something in its source changes. The source is only what the suite reads.
          check = name: { fileset, inputs, script }: pkgs.stdenvNoCC.mkDerivation {
            name = "atlas-${name}";
            src = source fileset;
            nativeBuildInputs = inputs;
            buildPhase = ''
              runHook preBuild
              patchShebangs scripts
              ${script}
              runHook postBuild
            '';
            installPhase = "touch $out";
          };

          # The npm packages of the browser-side tests, fetched one by one from the lock file.
          testJsNodeModules = pkgs.importNpmLock.buildNodeModules {
            npmRoot = ./frontend/test-js;
            nodejs = pkgs.nodejs_22;
          };
        in
        {
          packages = {
            inherit atlas atlas-app;
            default = atlas;
          };

          checks = {
            inherit atlas-app;

            gleam-test = check "gleam-test" {
              fileset = lib.fileset.difference ./frontend ./frontend/test-js;
              inputs = with pkgs; [ gleam beam27Packages.erlang beam27Packages.rebar3 nodejs_22 ];
              script = ''
                ${useHexPackages}
                cd frontend && gleam test
              '';
            };

            backend-test = check "backend-test" {
              fileset = lib.fileset.unions [ ./backend ./scripts/test-backend.sh ];
              inputs = with pkgs; [ nodejs_22 pocketbase ];
              script = "scripts/test-backend.sh";
            };

            frontend-js-test = check "frontend-js-test" {
              fileset = lib.fileset.unions [
                (lib.fileset.difference ./frontend ./frontend/test)
                ./backend
                ./scripts/build-frontend.sh
                ./scripts/test-frontend-js.sh
              ];
              inputs = with pkgs; [ gleam beam27Packages.erlang beam27Packages.rebar3 bun nodejs_22 pocketbase ];
              script = ''
                ${useHexPackages}
                ${useSystemBun}
                ln -s ${testJsNodeModules}/node_modules frontend/test-js/node_modules
                ATLAS_BUILD_ID=check ATLAS_NPM_INSTALL=0 scripts/test-frontend-js.sh
              '';
            };
          };
        };
    in
    {
      packages = forAll (pkgs: (atlasFor pkgs).packages);

      # The VM test of the NixOS module needs Linux (ADR 0090).
      checks = forAll (pkgs: (atlasFor pkgs).checks // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        nixos-module = pkgs.testers.runNixOSTest (import ./nix/nixos/test.nix { module = self.nixosModules.default; });
      });

      # The production server (ADR 0091). It exists once the server's hardware-configuration.nix has been copied
      # into nix/hosts/atlas; the system for it comes from that file (`nixpkgs.hostPlatform`).
      nixosConfigurations = nixpkgs.lib.optionalAttrs (builtins.pathExists ./nix/hosts/atlas/hardware-configuration.nix) {
        atlas = nixpkgs.lib.nixosSystem {
          modules = [ self.nixosModules.default ./nix/hosts/atlas ];
        };
      };

      # Atlas as a systemd service: `services.atlas` (ADR 0090).
      nixosModules.default = import ./nix/nixos/module.nix {
        atlasPackages = self.packages;
        flakePkgs = nixpkgs.legacyPackages;
      };

      apps = forAll (pkgs: {
        default = {
          type = "app";
          meta.description = "Run Atlas: PocketBase serving the built app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.atlas}/bin/atlas";
        };
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            gleam
            beam27Packages.erlang
            beam27Packages.rebar3
            pocketbase
            nodejs_22
            bun
            git
            curl
            unzip
            gnused
            gawk
            findutils
            coreutils
            gnugrep
            bash
          ];

          shellHook = ''
            # .tool-versions pins the versions the project is tested with; the
            # nixpkgs channel may carry different ones, so say so instead of
            # failing silently.
            if [ -f .tool-versions ]; then
              check() {
                want=$(awk -v t="$1" '$1 == t { print $2 }' .tool-versions)
                if [ -n "$want" ] && [ -n "$2" ] && [ "$want" != "$2" ]; then
                  echo "atlas: $1 is $2 here, .tool-versions pins $want" >&2
                fi
              }
              check gleam "$(gleam --version | awk '{ print $2 }')"
              check pocketbase "$(pocketbase --version | awk '{ print $NF }')"
            fi
          '';
        };
      });
    };
}
