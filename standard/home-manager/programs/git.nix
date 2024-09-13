{pkgs, ...}: {
  programs.git = {
    enable = true;
    userName = "XSnow";
    userEmail = "Slow@xsnow.live";
    extraConfig = {
      user.signingkey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDNa8/w2PpcOGxeFv9t/inf0t1W0Dvk4Ca2tl0T7ms4dy+F56FfGADWYgeCa8Hq7yNB9I7REfdo1c9OAYeOJmKKoeAfYHIV8GC8+u8CVIEEXxTT4nC5eC27kEij1UE/KTGuEKzNmICuAul5SR4EOCTpX/a08SM4tXYjMT8xyYRNbL/VBT7aOMBAtQhyIgnx96tdEBms5rzdI2l8MFgxvpK5ulxj07NlPX3zSIZG7Y1EmRPQedU88nOK9HBvk8yp1Nl3o+CjGB8ulj03sCCGQUhOBfORK5u+qSzLpHgzNOKQH4FkipbMZ4BM0LldrK9YVav9BBaCmcpLZOe9rSZJDUB8ldUGwc2bir07NYUizzEy9A07danb83hWJVmglfrAhr20hFf+MPxoc4ipccd757GQxmxDRyv5snkUyRZ2Rqb9Z9wMtJ1ikIeze6yY/W4vTMQdMJDmBwUNXRlAFyuj/5nXVSPLlO6yewNHRBkVvDYxeJMt7ExSFBwPDyt0507gIFU=";
      gpg = {
        format = "ssh";
        "ssh".program = "${pkgs._1password-gui}/bin/op-ssh-sign";
      };
      commit.gpgsign = true;
    };
  };
}