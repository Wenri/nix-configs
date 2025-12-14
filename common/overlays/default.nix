# This file defines overlays
{inputs, ...}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs {pkgs = final;};

  # This one contains whatever you want to overlay
  modifications = final: prev: {
    # NOTE: glibc built separately in flake.nix to avoid triggering mass rebuilds.
    # Android-patched glibc is available via androidGlibc package and used via LD_LIBRARY_PATH.
    # This allows using binary cache for all other packages while using custom glibc at runtime.
    # Patches preserved in ./glibc.nix and ./patches/glibc-termux/.

    fcitx5-rime-lua = prev.fcitx5-rime.overrideAttrs (_: {
      buildInputs = [prev.fcitx5 final.librime-lua];
    });
    fakechroot = prev.fakechroot.overrideAttrs (import ./fakechroot.nix final);
  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.system;
      config.allowUnfree = true;
    };
  };

  master-packages = final: _prev: {
    master = import inputs.nixpkgs-master {
      system = final.system;
      config.allowUnfree = true;
    };
  };

  # Make store paths work outside proot by using absolute symlinks
  absolute-symlinks = import ./absolute-symlinks.nix {inherit inputs;};
}
