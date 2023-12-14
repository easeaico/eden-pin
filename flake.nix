{
  description = "Dev environment for zig-c-simple";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }@inputs :
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.zig
        ];

        shellHook = ''
          echo "zig" "$(zig version)"
        '';
      };
    });
}
