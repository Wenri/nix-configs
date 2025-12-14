# Absolute Symlinks for Nix Store

## Problem

By default, Nix creates symlinks using paths relative to `/nix/store`. Inside the proot environment, this works fine because `/nix` is bound to `/data/data/com.termux.nix/files/usr/nix`. However, **outside proot**, these symlinks are broken because `/nix/store` doesn't exist on Android.

## Solution

The `absolute-symlinks` overlay rewrites symlinks in package outputs to use the absolute path `/data/data/com.termux.nix/files/usr/nix/store` instead of `/nix/store`. This makes the store paths accessible both inside and outside the proot environment.

## How It Works

1. **Overlay**: `common/overlays/absolute-symlinks.nix` provides a `makeAbsoluteSymlinks` function
2. **Post-processing**: For each package, it finds all symlinks and rewrites those pointing to `/nix/store`
3. **Absolute prefix**: Symlinks are rewritten to use `/data/data/com.termux.nix/files/usr/nix/store`
4. **Compatibility**: Works both inside proot (where both paths exist) and outside proot

## Usage

The overlay is automatically applied to nix-on-droid configurations. You can also use it manually:

```nix
# In your configuration
environment.packages = [
  (pkgs.lib.makeAbsoluteSymlinks pkgs.somePackage)
];
```

## Example

**Before** (default Nix):
```bash
$ readlink /nix/store/xxx-foo/bin/bar
/nix/store/yyy-dependency/bin/baz
```

**After** (with absolute-symlinks overlay):
```bash
$ readlink /nix/store/xxx-foo/bin/bar
/data/data/com.termux.nix/files/usr/nix/store/yyy-dependency/bin/baz
```

## Note

Currently, the overlay overrides `buildEnv` (used by `nix-env`, `nix-build --out-link`, etc.). This means profile generations will use absolute symlinks. Individual packages in the store still use relative symlinks, but environment compositions will work outside proot.

To extend this to more packages, you can override specific packages in the overlay's `modifications` section.
