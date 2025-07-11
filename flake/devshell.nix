{ ... }: {
  perSystem = { pkgs, ... }: {
    devShells = {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [
          sops
          nixd
          whisper-cpp
        ];
      };
    };
  };
}
