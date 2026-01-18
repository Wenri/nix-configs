# Core development packages (no texlive, no NUR dependencies)
# Works on all platforms including Android and WSL
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
  miscLanguages = with pkgs; [
    agda
    elixir
    octave
    typst
    tinymist
  ];
in {
  home.packages =
    [pythonEnv]
    ++ miscLanguages
    ++ haskellToolchain
    ++ rustToolchain
    ++ goToolchain;
}
