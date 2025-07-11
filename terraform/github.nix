{ config, ... }: {
  imports = [
    ./sops.nix
  ];

  terraform = {
    required_providers = {
      github = {
        source = "integrations/github";
      };
    };
  };

  provider = {
    github = {
      token = config.data.sops_file.secrets "data[\"github.token\"]";
    };
  };

  resource = {
    github_repository.mnemosyne = {
      name = "mnemosyne.el";
      description = "Emacs package to auto record, transcribe, and summarize system audio using whisper-cpp & gptel";
      visibility = "public";
    };
  };
}
