{
  description = "TaskChamp – TaskWarrior iOS client";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.tuist
          pkgs.rustc
          pkgs.cargo
          pkgs.libiconv
        ];

        shellHook = ''
          # Tuist uses DEVELOPER_DIR + xcrun to find swift. Nix's stdenv sets
          # DEVELOPER_DIR to the nix-store apple-sdk which doesn't have swift.
          # Override to point at the real Xcode installation.
          export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
          export SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
          export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$DEVELOPER_DIR/usr/bin:/usr/bin:$PATH"
          echo "TaskChamp dev shell — tuist $(tuist version 2>/dev/null || echo '?'), swift $(swift --version 2>&1 | head -1)"
        '';
      };
    };
}
