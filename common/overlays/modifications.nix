# Package modifications overlay
# Parameters:
#   lib             - nixpkgs lib
#   installationDir - Android installation directory for path translation (optional)
{ lib, installationDir ? null }: final: prev: {
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

  # Android: Node.js makes direct syscalls that bypass fakechroot's LD_PRELOAD path translation.
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
}
