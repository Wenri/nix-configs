{
  lib,
  pkgs,
  ...
}: {
  environment.systemPackages = lib.mkBefore (map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.vim
    pkgs.wget
    pkgs.jq
  ]);
}
