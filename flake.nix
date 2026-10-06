{
  description = "Atlas development shell (Gleam + Lustre frontend, PocketBase backend)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            gleam
            erlang_27
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
