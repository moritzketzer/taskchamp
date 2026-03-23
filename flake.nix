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
          # Xcode toolchain (swift, xcodebuild) must be on PATH for Tuist
          export PATH="/usr/bin:$PATH"
          export DEVELOPER_DIR="$(xcode-select -p)"
          echo "TaskChamp dev shell — tuist $(tuist version), rustc $(rustc --version | cut -d' ' -f2)"
        '';
      };
    };
}
