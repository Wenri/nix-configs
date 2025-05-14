{pkgs, ...}: {
  home.packages = with pkgs;
  with coqPackages_8_19;
  with nur.repos.chen; [
    coq
    lngen
    ott-sweirich
];

#    coq_8_20
#    metalib

  home.sessionVariables = {
    COQPATH = "$HOME/.nix-profile/lib/coq/8.19/user-contrib";
  };
}
