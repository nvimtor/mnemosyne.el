{ inputs, ... }: {
  imports = [
    inputs.terranix.flakeModule
  ];

  perSystem = { pkgs, lib, system, ... }: let
    inherit (lib) getName;

    # TODO extend?
    pkgs' = import inputs.nixpkgs {
      inherit system;

      config = {
        allowUnfreePredicate = pkg: builtins.elem (getName pkg) [
          "terraform"
        ];
      };
    };
  in {
    terranix = {
      terranixConfigurations = {
        terraform = {
          modules = [
            ../terraform
          ];

          extraArgs = {
            input = false;
          };

          terraformWrapper.package = pkgs'.terraform.withPlugins (ps: with ps; [
            sops
            github
          ]);

          workdir = ".";
        };
      };
    };
  };
}
