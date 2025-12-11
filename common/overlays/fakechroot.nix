# Fakechroot from Wenri's fork (forked from lipnitsk)
final: oldAttrs: {
  version = "unstable-2021-02-26";
  src = final.fetchFromGitHub {
    owner = "Wenri";
    repo = "fakechroot";
    rev = "e7c1f3a446e594a4d0cce5f5d499c9439ce1d5c5";
    hash = "sha256-a4bA7iGLp47oJ0VGNbRG/1mMS9ZjtD3IcHZ02YwyTD0=";
  };
  # Remove patches that are already integrated upstream
  patches = [];
}
