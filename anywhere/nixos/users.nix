{pkgs, ...}: {
  users.users = {
    wenri = {
      # TODO: You can set an initial password for your user.
      # If you do, you can skip setting a root password by passing '--no-root-passwd' to nixos-install.
      # Be sure to change it (using passwd) after rebooting!
      initialPassword = "correcthorsebatterystaple";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        # TODO: Add your SSH public key(s) here, if you plan on using SSH to connect
      ];
      # TODO: Be sure to add any other groups you need (such as networkmanager, audio, docker, etc)
      description = "Bingchen Gong";
      extraGroups = [ "networkmanager" "wheel" "docker" ];
      packages = with pkgs; [
        #  thunderbird
      ];
      shell = pkgs.zsh;
    };

    root = {
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCnOOmUOZ9Zbdgoywwpe2cNKvndWTwHGsX+mdCgQwt9dwAqUTYg/TTPdYzM/v6iiB93dEZmcHqjVnWysDaOycbpWSB0utI/qsQcp1QB0xweHFDchQZsLovixIwlilO4gU4jH51KAxdLlhVcoxDgYQ5sKslnhfwbEkbXU2ddzICBTkSGeh7B7wPJUWQqHRle+I7C2AUMkwXO+BaacsxF9dZ7wFRVLOx9EZl4mD+bLi///WJ7jIZR7abx34FGf16Oez4N+GJCLgzpcTnMEga6lXSWYWXq3Udn+4KgvQpwAcLa65c48HcshMi+jnZonroihZ8zr1iNcZgb+LLJYj94nnnM9DIQ6ptMYNnr6Lmlqbx354KYUW+8JD4manmyoQ97mosZE6LneSVYSXfg1burTG51gb117GAWecaTv8rmkJix0+3W/uSRBHar+w6dvLnDfw4wndbo5K4LQqxxn5JxUUS14wcglEmlle4ZfttCdTFf9q9r3kxjip2+PBMr54xVHV7iH+zSDEJk6+u/oOhHSTrc0GfWV9kswpHtAI87FFyJ0/denQcXVU+bg93D8NibYZcFj0DmzwA8qae5rRYPXEMHEV2TU+5OrinxV3ySkVETcUFIuOGewBf9PlwgXQMmYiS5f4+ZpZyUd9TdmfXOGlRDySn0MPjV4gwgRXfq06lKFQ=="
      ];
    };
  };

  # Enable passwordless sudo for wheel group
  security.sudo.wheelNeedsPassword = false;

  programs.zsh.enable = true;
  programs.firefox.enable = true;
  services.printing.browsed.enable = false;
}
