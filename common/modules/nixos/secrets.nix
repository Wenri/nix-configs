{
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = ["xsnow"];
  };

  programs._1password.enable = true;

  # The 1Password SSH agent needs to be turned on manually to create ~/.1password/agent.sock
}
