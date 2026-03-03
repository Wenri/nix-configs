# Package modifications overlay
# Parameters:
#   lib             - nixpkgs lib
#   installationDir - Android installation directory for path translation (optional)
{ inputs, lib, installationDir ? null }: final: prev: {
  # NOTE: glibc and fakechroot for Android are built separately in common/pkgs/.
  # Android-patched glibc is available via androidGlibc package.
  # See common/pkgs/android-glibc.nix and common/pkgs/android-fakechroot.nix.

  # Desktop: fcitx5-rime with Lua support
  fcitx5-rime-lua = prev.fcitx5-rime.overrideAttrs (_: {
    buildInputs = [ prev.fcitx5 final.librime-lua ];
  });

  # Android: autoPatchelfHook fails due to Python prefix detection issue.
  # When Python runs via shebang, the wrapper's --inherit-argv0 sets argv[0] to script path,
  # causing Python to use base prefix instead of env prefix (missing pyelftools).
  # Workaround: skip autoPatchelf and use replaceAndroidDependencies instead.
  cursor-cli = prev.cursor-cli.overrideAttrs (_: {
    dontAutoPatchelf = true;
  });

  github-copilot-cli = prev.github-copilot-cli.overrideAttrs (_: {
    dontAutoPatchelf = true;
  });

  # Android: Go binaries work with nix-ld (short interpreter path + NIX_LD_LIBRARY_PATH).
  # SSL certs and GODEBUG=netdns=cgo are set globally in home.sessionVariables.
  # Binaries with no RPATH skip RPATH patching to avoid patchelf corruption.

  # Bump netclient to v1.5.0 (nixpkgs has 1.1.0)
  netclient = prev.netclient.overrideAttrs {
    version = "1.5.0";
    src = prev.fetchFromGitHub {
      owner = "gravitl";
      repo = "netclient";
      rev = "v1.5.0";
      hash = "sha256-BhaWOfiGnkPn/G5uhVNX3RAz4XFllAl5b8RzfjafsU4=";
    };
    vendorHash = "sha256-xMzl3K4d6bUzWnUZq6ULcynqIe/ZTpiRptvHAhCnB6Q=";
    proxyVendor = true;
  };

  # Claude Code from claude-code-nix (Node.js runtime, hourly updates)
  # Android: additional path translation for fakechroot compatibility
  claude-code = let
    base = final.callPackage "${inputs.claude-code-nix}/package.nix" {
      runtime = "node";
      nodeBinName = "claude";
    };
  in if installationDir != null then
    final.symlinkJoin {
      name = "claude-code-${base.version}";
      paths = [ base ];
      postBuild = ''
        rm $out/bin/claude
        substitute ${base}/bin/claude $out/bin/claude \
          --replace "${base}/lib" "${installationDir}${base}/lib" \
          --replace "exec " "export CLAUDE_CODE_TMPDIR='${installationDir}/tmp'"$'\n'"exec "
        chmod +x $out/bin/claude
      '';
    }
  else base;
}
