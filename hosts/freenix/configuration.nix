{
  lib,
  pkgs,
  hostname,
  outputs,
  ...
}: {
    imports = [
      outputs.nixosModules.server-base
      outputs.nixosModules.users
      outputs.nixosModules.netclient
    ];

  networking.hostName = hostname;

  # Use latest mainline kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Increase CIFS max buffer size (default 16KB, max 130048)
  # With SMB3 multi-credit, rsize/wsize = credits * CIFSMaxBufSize
  boot.extraModprobeConfig = "options cifs CIFSMaxBufSize=130048";

  # CIFS: mount Freebox NAS NVMe share over SMB3
  fileSystems."/mnt/nvmedata" = {
    device = "//192.168.1.254/nvmedata";
    fsType = "cifs";
    options = [
      "guest"
      "vers=3.1.1"
      "posix"
      "hard"
      "cache=loose"
      "nostrictsync"
      "nodfs"
      "noatime"
      "_netdev"
      "nofail"
      "x-systemd.mount-timeout=30"
    ];
  };

  environment.systemPackages = [pkgs.cifs-utils];

  # 8GB swap file over CIFS (pre-created on NAS)
  swapDevices = [
    {
      device = "/mnt/nvmedata/VMs/freenix/swapfile";
      priority = 1;
      discardPolicy = "both";
    }
  ];

  # Configure systemd-networkd for both network interfaces
  # Tailscale optimization will be auto-detected based on MAC addresses below
  # Match by MAC address for stability (interface names can change)
  # IPv4: DHCP
  # IPv6: Automatic configuration via Router Advertisements
  systemd.network.networks."40-enp0s5" = {
    matchConfig = {
      MACAddress = "9e:c4:c5:11:3a:96"; # enp0s5
    };
    enable = true;
    linkConfig.MTUBytes = "65535";
    networkConfig = {
      DHCP = "yes"; # Enable IPv4 DHCP
      IPv6AcceptRA = true; # IPv6 Router Advertisement configuration
    };
  };

  systemd.network.networks."40-enp0s8u1" = {
    matchConfig = {
      MACAddress = "2c:16:db:a1:3b:e5"; # enp0s8u1
    };
    enable = true;
    networkConfig = {
      DHCP = "yes"; # Enable IPv4 DHCP
      IPv6AcceptRA = true; # IPv6 Router Advertisement configuration
    };
  };

  # One-time: remove ext4 journal before root is mounted
  # Remove this block after successful reboot with journal removed
  boot.initrd.extraUtilsCommands = ''
    copy_bin_and_libs ${pkgs.e2fsprogs}/bin/tune2fs
  '';
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    if tune2fs -l /dev/mapper/pool-root 2>/dev/null | grep -q "has_journal"; then
      echo "Removing ext4 journal from /dev/mapper/pool-root..."
      tune2fs -O ^has_journal /dev/mapper/pool-root
      fsck.ext4 -fy /dev/mapper/pool-root
      echo "Journal removed successfully."
    fi
  '';

  # Mitigate kswapd GFP_NOFAIL warning (2GB RAM):
  # - zram 100%: more swap headroom reduces memory pressure
  # - watermark_boost_factor=0: prevent kswapd watermark boosting that causes
  #   thrashing on low-memory systems
  # - min_free_kbytes=65536: keep 64MB free to avoid extreme pressure paths
  zramSwap.memoryPercent = 100;
  boot.kernel.sysctl = {
    "vm.watermark_boost_factor" = 0;
    "vm.min_free_kbytes" = 65536;
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
