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

  # ext4 performance: writeback mode skips data journaling, async commit reduces sync overhead
  fileSystems."/".options = lib.mkAfter [
    "data=writeback"
    "journal_async_commit"
  ];

  # Mitigate kswapd/jbd2 GFP_NOFAIL warning (2GB RAM, single DMA zone):
  # - Increase zram to 100% of RAM for more swap headroom
  # - Evict dentry/inode caches earlier to avoid kswapd triggering jbd2 allocations
  # - Keep more free memory to avoid extreme pressure paths
  zramSwap.memoryPercent = 100;
  boot.kernel.sysctl = {
    "vm.vfs_cache_pressure" = 200;
    "vm.min_free_kbytes" = 65536;
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
