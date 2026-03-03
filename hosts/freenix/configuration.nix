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

  # Rename interfaces by MAC address for clarity
  systemd.network.links."10-ovhcloud0" = {
    matchConfig.MACAddress = "2c:16:db:a1:3b:e5";
    linkConfig.Name = "ovhcloud0";
  };
  systemd.network.links."10-freebox0" = {
    matchConfig.MACAddress = "9e:c4:c5:11:3a:96";
    linkConfig.Name = "freebox0";
  };

  # Configure systemd-networkd for both network interfaces
  # Match by MAC address for stability

  # ovhcloud0 (2c:16:db:a1:3b:e5) - primary, OVHcloud uplink
  systemd.network.networks."10-ovhcloud0" = {
    matchConfig.MACAddress = "2c:16:db:a1:3b:e5";
    enable = true;
    networkConfig = {
      DHCP = "yes";
      IPv6AcceptRA = true;
    };
    dhcpV4Config.RouteMetric = 100;
  };

  # freebox0 (9e:c4:c5:11:3a:96) - Freebox LAN
  systemd.network.networks."40-freebox0" = {
    matchConfig.MACAddress = "9e:c4:c5:11:3a:96";
    enable = true;
    linkConfig.MTUBytes = "65535";
    networkConfig = {
      DHCP = "yes";
      IPv6AcceptRA = true;
    };
    dhcpV4Config.RouteMetric = 200;
  };


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
