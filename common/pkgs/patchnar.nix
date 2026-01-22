# patchnar - NAR stream patcher for Android compatibility
# Patches ELF binaries, symlinks, and scripts within NAR streams
{ stdenv, autoreconfHook, autoconf-archive, pkg-config, boost, sourceHighlight, patchnarSrc ? null }:

let
  src = if patchnarSrc != null then patchnarSrc else ../../../submodules/patchnar;
in
stdenv.mkDerivation {
  pname = "patchnar";
  version = "0.22.0";

  inherit src;

  nativeBuildInputs = [ autoreconfHook autoconf-archive pkg-config ];
  buildInputs = [ boost sourceHighlight ];

  # Build both patchelf and patchnar
  # patchnar includes all patchelf functionality plus NAR processing
  postInstall = ''
    # Verify both binaries are installed
    test -x $out/bin/patchelf
    test -x $out/bin/patchnar
  '';

  meta = {
    description = "NAR stream patcher for Android (based on patchelf)";
    homepage = "https://github.com/Wenri/patchnar";
    license = stdenv.lib.licenses.gpl3Plus or "GPL-3.0-or-later";
  };
}
