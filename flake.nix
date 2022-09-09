{
  description = "Gleam wrapper for erlexec";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.05";
    gleam-nix = {
      url = "github:manveru/gleam-nix";
      inputs.gleam.url = "github:gleam-lang/gleam";
    };
  };

  outputs = {
    self,
    nixpkgs,
    gleam-nix,
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
        gleam-nix.packages.${system}.gleam
        pkgs.erlangR25
        pkgs.rebar3
        self.packages.${system}.erl-format
      ];
    };
  };
}
