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

    # NOTE: fakechroot for Android is now built with compile-time hardcoded paths in flake.nix.
    # The androidFakechroot package has all FAKECHROOT_ANDROID_* macros defined at build time.
    # See submodules/fakechroot/src/android-config.h for the required compile-time definitions.

    fcitx5-rime-lua = prev.fcitx5-rime.overrideAttrs (_: {
      buildInputs = [prev.fcitx5 final.librime-lua];
    });

    # autoPatchelfHook fails on Android/nix-on-droid due to Python prefix detection issue:
    # When Python runs via shebang, the wrapper's --inherit-argv0 sets argv[0] to script path,
    # causing Python to use base prefix instead of env prefix (missing pyelftools).
    # Workaround: skip autoPatchelf and use patchPackageForAndroidGlibc instead.
    cursor-cli = prev.cursor-cli.overrideAttrs (_: {
      dontAutoPatchelf = true;
    });

    github-copilot-cli = prev.github-copilot-cli.overrideAttrs (_: {
      dontAutoPatchelf = true;
    });
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
}
