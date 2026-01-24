# patchnar - NAR stream patcher for Android compatibility
# Patches ELF binaries, symlinks, and scripts within NAR streams
{ stdenv, gcc14Stdenv, lib, autoreconfHook, autoconf-archive, pkg-config, boost, sourceHighlight, patchnarSrc }:
# Use GCC 14 stdenv for C++23 support (std::generator)
gcc14Stdenv.mkDerivation {
  pname = "patchnar";
  version = "0.22.0";

  src = patchnarSrc;

  nativeBuildInputs = [ autoreconfHook autoconf-archive pkg-config ];
  buildInputs = [ boost sourceHighlight ];

  # Set source-highlight data directory at compile time
  configureFlags = [
    "--with-source-highlight-data-dir=${sourceHighlight}/share/source-highlight"
  ];

  # patchnar includes all patchelf functionality as a library
  postInstall = ''
    # Verify patchnar is installed
    test -x $out/bin/patchnar
  '';

  meta = {
    description = "NAR stream patcher for Android (based on patchelf)";
    homepage = "https://github.com/Wenri/patchnar";
    license = lib.licenses.gpl3Plus;
  };
}
