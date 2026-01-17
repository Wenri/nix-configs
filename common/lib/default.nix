# common/lib/default.nix
# Export library functions for Android integration
{
  replaceAndroidDependencies = import ./replace-android-dependencies.nix;
}
