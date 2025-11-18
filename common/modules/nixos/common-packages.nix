{
  lib,
  pkgs,
  ...
}: {
  environment.systemPackages =
    lib.mkBefore (map lib.lowPrio [
      pkgs.curl
      pkgs.gitMinimal
      pkgs.vim
      pkgs.wget
      pkgs.jq
      pkgs.ethtool
      pkgs.usbutils
      pkgs.ndisc6
      pkgs.iputils
      (pkgs.writeShellScriptBin "ping6" ''
        exec ${pkgs.iputils}/bin/ping -6 "$@"
      '')
    ]);
}
