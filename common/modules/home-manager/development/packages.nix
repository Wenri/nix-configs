{pkgs, ...}: let
  packages = import ../../../packages.nix {inherit pkgs;};
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [requests]);
  haskellToolchain = with pkgs.haskellPackages; [
    ghc
    stack
    cabal-install
    haskell-language-server
  ];
  latexStack = with pkgs; [
    texlive.combined.scheme-full
    python3Packages.pygments
  ];
  miscLanguages = with pkgs; [
    agda
    elixir
    typst
    tinymist
  ];
in {
  home.packages =
    latexStack
    ++ [pythonEnv]
    ++ miscLanguages
    ++ haskellToolchain
    ++ packages.rustToolchain
    ++ packages.goToolchain;
}
