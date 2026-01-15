# Additional nixpkgs channels overlay
# Provides access to unstable and master packages via pkgs.unstable.* and pkgs.master.*
{ inputs }: {
  # Access nixpkgs-unstable via pkgs.unstable.*
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.system;
      config.allowUnfree = true;
    };
  };

  # Access nixpkgs-master via pkgs.master.*
  master-packages = final: _prev: {
    master = import inputs.nixpkgs-master {
      system = final.system;
      config.allowUnfree = true;
    };
  };
}
