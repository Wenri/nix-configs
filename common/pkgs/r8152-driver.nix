{ stdenv, lib, kernel }:

stdenv.mkDerivation {
  pname = "r8152";
  version = "2.21.4";

  src = ./r8152-2.21.4.tar.bz2;
  sourceRoot = ".";

  hardeningDisable = [ "pic" ];
  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = [
    "KERNELDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  buildFlags = [ "modules" ];

  installPhase = ''
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$(pwd) INSTALL_MOD_PATH=$out INSTALL_MOD_DIR=updates \
      modules_install
  '';

  meta = with lib; {
    description = "Realtek RTL8152/RTL8153/RTL8156 USB Ethernet driver";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
  };
}
