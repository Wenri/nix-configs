# This file defines overlays
{inputs, lib ? inputs.nixpkgs.lib, installationDir ? null, ...}: {
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
    # Workaround: skip autoPatchelf and use replaceAndroidDependencies instead.
    cursor-cli = prev.cursor-cli.overrideAttrs (_: {
      dontAutoPatchelf = true;
    });

    github-copilot-cli = prev.github-copilot-cli.overrideAttrs (_: {
      dontAutoPatchelf = true;
    });

    # Go binaries work fine with standard glibc on Android - skip Android glibc patching
    # The Android glibc patching causes SIGSEGV crashes in Go binaries
    gh = prev.gh.overrideAttrs (old: {
      passthru = (old.passthru or {}) // { skipAndroidGlibcPatch = true; };
    });

    # Node.js makes direct syscalls that bypass fakechroot's LD_PRELOAD path translation.
    # Replace the cli.js path with the real Android filesystem path so node can find it.
    # Use symlinkJoin to avoid rebuilding (npm build also fails due to same syscall issue).
    claude-code = if installationDir != null then
      final.symlinkJoin {
        name = "claude-code-${prev.claude-code.version}";
        paths = [ prev.claude-code ];
        postBuild = ''
          rm $out/bin/claude $out/bin/.claude-wrapped
          substitute ${prev.claude-code}/bin/.claude-wrapped $out/bin/.claude-wrapped \
            --replace "${prev.claude-code}/lib" "${installationDir}${prev.claude-code}/lib"
          substitute ${prev.claude-code}/bin/claude $out/bin/claude \
            --replace "${prev.claude-code}/bin" "$out/bin"
          chmod +x $out/bin/claude $out/bin/.claude-wrapped
        '';
      }
    else prev.claude-code;
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
