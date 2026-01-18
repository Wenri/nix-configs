{pkgs, ...}: let
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [requests]);
  haskellToolchain = with pkgs.haskellPackages; [
    ghc
    stack
    cabal-install
    haskell-language-server
  ];
  rustToolchain = with pkgs; [
    rustc cargo rust-analyzer clippy rustfmt
  ];
  goToolchain = with pkgs; [
    go gopls delve go-tools
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
    ++ rustToolchain
    ++ goToolchain;
}
