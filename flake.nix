{
  description = "Atlas: Gleam + Lustre frontend on PocketBase (package, app and development shell)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (pkgs:
        let
          lib = pkgs.lib;

          # Only what the build reads, so unrelated edits do not rebuild the app.
          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./frontend/gleam.toml
              ./frontend/manifest.toml
              ./frontend/src
              ./frontend/assets
              ./backend/pb_hooks
              ./backend/pb_migrations
              ./scripts/build-frontend.sh
            ];
          };

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

          buildId = "${self.shortRev or self.dirtyShortRev or "dev"}-${self.lastModifiedDate or "0"}";

          # The built app: the static frontend plus the PocketBase hooks and migrations.
          atlas-app = pkgs.stdenvNoCC.mkDerivation {
            pname = "atlas-app";
            version = "0-${buildId}";
            inherit src;
            nativeBuildInputs = with pkgs; [ gleam beam27Packages.erlang beam27Packages.rebar3 bun git ];

            buildPhase = ''
              runHook preBuild
              export HOME=$TMPDIR/home
              mkdir -p $HOME/.cache/gleam/hex/hexpm
              cp -rL ${hexPackages} $HOME/.cache/gleam/hex/hexpm/packages
              chmod -R u+w $HOME
              # The Bun that lustre_dev_tools would download cannot run in the build sandbox.
              printf '\n[tools.lustre.bin]\nbun = "system"\n' >> frontend/gleam.toml
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
        in
        {
          inherit atlas atlas-app;
          default = atlas;
        });

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
