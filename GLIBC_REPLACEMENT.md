# glibc Replacement Strategy for nix-on-droid

## The Problem

You want to use Android-patched glibc with Nix packages, but replacing glibc causes all packages that depend on it to be rebuilt from source, which defeats the purpose of using the binary cache.

## Current Implementation: **patchelf Build-Time Replacement with Termux's System glibc**

The configuration now uses a **patchelf-based approach** that:
1. Downloads packages from binary cache (standard glibc 2.40)
2. Uses Termux's system glibc (2.41) installed at `/data/data/com.termux.nix/files/usr/lib`
3. Creates wrapper derivations that use `patchelf` to rewrite ELF headers
4. Replaces interpreter and RPATH references to point to Termux's glibc
5. Results in new store paths that work with Termux's Android-patched glibc

### How It Works

**In `flake.nix`:**
- `androidGlibc` - Creates a wrapper that symlinks to Termux's system glibc (fallback to nixpkgs glibc if not found)
- `patchPackageForAndroidGlibc` - Function that takes any package and creates a patched version
- Uses `runCommand` + `patchelf` to rewrite:
  - Interpreter: `/nix/store/.../glibc/lib/ld-linux-aarch64.so.1` → Termux glibc (2.41)
  - RPATH: References to standard glibc (2.40) → Termux glibc (2.41)

**In `common/modules/nix-on-droid/base.nix`:**
- All packages in `environment.packages` are automatically passed through `patchPackageForAndroidGlibc`
- Creates new store paths with patched binaries

**In `common/modules/home-manager/core/packages.nix`:**
- All home-manager packages are also patched for nix-on-droid
- Only applies on Android, desktop/server hosts remain unpatched

### What Gets Built

- ✅ Android-patched glibc (must be built from source)
- ✅ Small wrapper derivations for each package (fast, just runs patchelf)
- ❌ Original packages (downloaded from binary cache, not rebuilt)

### Advantages

- Uses binary cache for actual package content
- Only builds: (1) Android glibc, (2) small patchelf wrappers
- Much faster than full rebuilds
- Correct at runtime - binaries use Android glibc

### Caveats

1. **New store paths**: Patched packages have different paths than originals
2. **Disk space**: Both original + patched versions in store (can use `nix-collect-garbage`)
3. **Wrapper overhead**: Small derivation for each package
4. **Binary compatibility**: Assumes Android glibc is ABI-compatible with standard glibc

## Why This Happens

In Nix:
- Every package has a hash based on its inputs (dependencies)
- Changing glibc changes its hash
- Any package that depends on glibc will have a different hash
- Different hash = different /nix/store path = not in cache = must rebuild

## The Hard Truth

**There is NO way to replace glibc's binary files and still use binary cache for dependent packages.**

Here's why:
1. Nix store paths include dependency hashes (e.g., `/nix/store/abc123-bash` depends on `/nix/store/def456-glibc`)
2. If you change glibc, the hash changes (e.g., `/nix/store/xyz789-glibc-android`)
3. All packages now need `/nix/store/newHash-bash` that depends on the new glibc
4. These new paths aren't in the cache, so they must be built

## Available Options

### Option 1: Full Rebuild with Overlay (CURRENT IMPLEMENTATION)

**What it does:** 
- Builds Android-patched glibc
- Uses overlay to replace glibc in ALL packages
- Everything gets rebuilt with new glibc

**Pros:**
- ✅ Correct and safe
- ✅ All binaries properly linked against Android glibc
- ✅ No runtime surprises

**Cons:**
- ❌ Must rebuild ALL packages
- ❌ Takes a very long time (hours/days on Android)
- ❌ Requires lots of storage space

**Code:**
```nix
nixpkgs.overlays = [
  (final: prev: {
    glibc = androidGlibc;
  })
];
```

### Option 2: Runtime LD_LIBRARY_PATH Override (NOT IMPLEMENTED)

**What it does:**
- Uses binary cache for all packages (with standard glibc)
- Sets LD_LIBRARY_PATH to point to Android glibc
- Dynamic linker uses Android glibc at runtime

**Pros:**
- ✅ Uses binary cache
- ✅ Fast to build

**Cons:**
- ❌ Fragile - may break with symbol mismatches
- ❌ Not guaranteed to work for all binaries
- ❌ Requires true binary compatibility

**How to enable:**
Replace the overlay in `flake.nix` with:
```nix
{
  environment.packages = [ androidGlibc ];
  environment.sessionVariables = {
    LD_LIBRARY_PATH = "${androidGlibc}/lib";
    NIX_LD = "${androidGlibc}/lib/ld-linux-aarch64.so.1";
  };
}
```

### Option 3: Cross-compile on a Real Linux Machine (RECOMMENDED)

**What it does:**
- Build on a fast x86_64 Linux machine
- Cross-compile for aarch64-linux with Android glibc
- Copy store paths to Android device

**Pros:**
- ✅ Builds much faster on powerful machine
- ✅ Correct linking
- ✅ Can use binary cache for build tools

**Cons:**
- ❌ Requires a separate Linux machine
- ❌ Need to set up cross-compilation
- ❌ Must transfer to Android

**How to do it:**
```bash
# On Linux machine:
nix build --system aarch64-linux '.#nixOnDroidConfigurations.default.activationPackage'
nix copy --to ssh://android ./result

# On Android:
nix-store --realise /nix/store/...-activation
```

## Current Configuration

The current implementation uses **Option 1** (Full Rebuild with Overlay).

**Files modified:**
- `flake.nix`: Builds `androidGlibc` and applies it via overlay
- `common/overlays/default.nix`: Documents that glibc is handled in flake
- `common/overlays/glibc.nix`: Contains Android patches

**How it works:**
1. `androidGlibc` is built from clean nixpkgs with Android patches
2. Module applies overlay replacing `glibc` with `androidGlibc`
3. All packages in the configuration use the new glibc
4. Everything must be rebuilt since hashes changed

## Recommendations

**For development/testing:**
- Use Option 2 (LD_LIBRARY_PATH) if you just need basic functionality
- Fastest to build and test

**For production:**
- Use Option 3 (cross-compile) for best results
- Fast builds on powerful machine
- Proper linking and correctness

**Current setup (Option 1):**
- Only use if you must build everything on Android
- Be prepared for very long build times
- Ensure you have enough storage space

## Binary Compatibility Note

If your Android-patched glibc is truly binary compatible with the standard glibc (same symbols, same ABI), then Option 2 should work fine. However, this is not guaranteed and may cause subtle bugs.

**To test binary compatibility:**
```bash
# Run a simple binary with Android glibc
LD_LIBRARY_PATH=/path/to/android-glibc/lib bash --version

# If it works, you probably have binary compatibility
# If it crashes or shows errors, you need full rebuilds (Option 1 or 3)
```

## Build Time Estimates

On a typical Android device:
- **Current (patchelf):** 2-4 hours (glibc + small wrappers)
- **Option 1 (Overlay):** 12-48 hours (full system rebuild)
- **Option 2 (LD_LIBRARY_PATH):** 1-3 hours (just glibc)
- **Option 3 (Cross-compile):** 1-2 hours on fast Linux machine

## Storage Requirements

- **Current (patchelf):** ~10-15 GB (binary cache + patched wrappers + glibc)
- **Option 1:** ~15-30 GB (all packages built)
- **Option 2:** ~5-10 GB (binary cache + glibc)
- **Option 3:** ~10-20 GB (transferred store paths)

## Usage

### To Build and Activate

```bash
# Stage changes
git add .

# Build and switch
nix-on-droid switch --flake ~/.config/nix-on-droid
```

### To Add More Packages

In your configuration file, packages added to `environment.packages` are automatically patched:

```nix
# In hosts/nix-on-droid/configuration.nix or any imported module
{
  environment.packages = [ pkgs.vim pkgs.git ];  # Automatically patched
}
```

### Manual Patching

If you need to manually patch a package:

```nix
{
  environment.packages = [
    (patchPackageForAndroidGlibc pkgs.somePackage)
  ];
}
```

### Verify Patching

After building, check if a binary uses Android glibc:

```bash
# Check interpreter
patchelf --print-interpreter $(which bash)
# Should show: /nix/store/.../android-glibc-.../lib/ld-linux-aarch64.so.1

# Check RPATH
patchelf --print-rpath $(which bash)
# Should include Android glibc paths
```

## Troubleshooting

### Package Fails to Run

If a patched package fails:
1. Check if it's an ELF binary: `file $(which program)`
2. Verify interpreter: `patchelf --print-interpreter $(which program)`
3. Check for missing libraries: `ldd $(which program)`

### ABI Incompatibility

If you get symbol version errors, the Android glibc may not be fully compatible. Options:
- Rebuild that specific package from source with Android glibc
- Use runtime LD_LIBRARY_PATH for that package only
- Switch to full rebuild approach (Option 1)

### Disk Space Issues

If running low on space:
```bash
# Remove old generations
nix-collect-garbage -d

# Remove original (unpatched) packages if confident
nix-store --gc --max-freed 5G
```
