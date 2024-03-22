{
  description = "Gleam wrapper for erlexec";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    packages.${system} = {
      erl-format = pkgs.writeShellApplication {
        name = "erl-format";
        runtimeInputs = [pkgs.rebar3];
        text = ''
          for f in "$@"; do
            rebar3 fmt -w "$f"
          done
        '';
      };
    };

    devShells.${system}.default = pkgs.mkShell {
      packages = [
        pkgs.gleam
        pkgs.erlang_nox
        pkgs.rebar3
        self.packages.${system}.erl-format
      ];
    };
  };
}
