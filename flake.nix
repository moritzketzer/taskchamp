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
          # Tuist + Xcode need the real Apple toolchain, not Nix wrappers.
          # Override DEVELOPER_DIR, SDKROOT, and clear Nix build flags that
          # leak into xcodebuild and break the linker.
          export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
          export SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
          export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$DEVELOPER_DIR/usr/bin:/usr/bin:$PATH"
          unset NIX_LDFLAGS NIX_CFLAGS_COMPILE MACOSX_DEPLOYMENT_TARGET LD CC CXX NIX_CC NIX_ENFORCE_NO_NATIVE NIX_HARDENING_ENABLE NIX_CC_WRAPPER_TARGET_HOST_arm64_apple_darwin
          echo "TaskChamp dev shell — tuist $(tuist version 2>/dev/null || echo '?'), swift $(swift --version 2>&1 | head -1)"
        '';
      };
    };
}
