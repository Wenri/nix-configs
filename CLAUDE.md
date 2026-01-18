# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS configuration repository based on the [nix-starter-config](https://github.com/Misterio77/nix-starter-config) template. It contains:
- **Single unified flake** at root managing 6 NixOS hosts + 1 nix-on-droid (Android)
- **Unified infrastructure** in `common/` (overlays, modules, packages, home-manager)
- **Per-host configurations** in `hosts/` directory
- **All users are the same person: Bingchen Gong (username: wenri)**

## Repository Structure

### common/ - Unified Infrastructure (Exported)

Shared infrastructure providing identical userspace across all 6 hosts:

**Infrastructure** (all exported via flake outputs):
- `overlays/default.nix` - Package overlays:
  - `additions` - Custom packages from common/pkgs
  - `modifications` - Package modifications (e.g., fcitx5-rime-lua)
  - `unstable-packages` - Access to nixpkgs-unstable via `pkgs.unstable.*`
  - `master-packages` - Access to nixpkgs-master via `pkgs.master.*`
  - NUR (Nix User Repository) integration for community packages
  - nix-vscode-extensions for VS Code marketplace extensions
  - `modules/nixos/` - Exportable NixOS modules:
    - `common-base.nix` - Shared overlays + nix settings used everywhere
    - `server-base.nix` - Base server configuration with overlays
  - `users.nix` - Desktop user configuration
  - `locale.nix` - Locale and timezone settings
  - `secrets.nix` - Secrets management configuration
  - `tailscale.nix` - Tailscale VPN configuration
  - `disk-config.nix` - Disko disk partitioning
- `modules/home-manager/` - Empty, ready for exportable home-manager modules
- `pkgs/` - Custom package definitions (example-package)

**Core home-manager modules** (auto-imported via `common/home-manager/default.nix`):
- `core/default.nix` - Core profile combining CLI essentials + git/zsh/ssh/gh/program defaults
- `core/packages.nix` - Essential CLI tools (tmux, htop, nodejs, claude-code, cursor-cli, gemini-cli, iperf3, jq, file, parted)
- `core/programs.nix` - Base program enables (home-manager, tmux, vim)
- `core/git.nix` - Complete git configuration with user details, 1Password SSH signing
- `core/zsh.nix` - Complete zsh configuration (oh-my-zsh, completion, syntax highlighting, history)
- `core/ssh.nix` - SSH configuration with 1Password agent, GitHub port 443 workaround
- `core/gh.nix` - GitHub CLI configuration

**Optional home-manager modules** (imported explicitly when needed):
- `desktop/packages.nix` - GUI applications (Discord, Slack, Zoom, Chrome, etc.)
- `desktop/default.nix` - Desktop program bundle (Firefox, VS Code, Emacs, GNOME, Rime, optional WeChat)
- `desktop/emacs.nix`, `desktop/firefox`, `desktop/gnome`, `desktop/rime`, `desktop/vscode`, `desktop/wechat` - individual program modules
- `development/packages.nix` - Language/toolchain bundles (Agda, Elixir, Haskell, LaTeX, Python, Typst)
- `development/coq.nix` - Coq proof assistant with NUR packages (lngen, ott-sweirich)
- `development/pcloud.nix` - pCloud with patches
  - `rime/` - Rime input method
  - `vscode/` - VS Code settings and vscode-marketplace extensions
  - `emacs.nix` - Emacs configuration
  - `firefox/` - Firefox with NUR extensions (1Password, uBlock Origin, Translate)
  - `gnome.nix` - GNOME desktop customizations

**Result**: All 6 hosts share identical userspace and infrastructure.

### Root flake.nix - Single Unified Flake

The root `flake.nix` manages all 6 hosts with a single source of truth:

```nix
hosts = {
  wslnix       = { system = "x86_64-linux";   username = "wenri"; type = "wsl"; };
  nixos-gnome  = { system = "x86_64-linux";   username = "wenri"; type = "desktop"; };
  nixos-plasma6= { system = "x86_64-linux";   username = "wenri"; type = "desktop"; };
  irif         = { system = "x86_64-linux";   username = "wenri"; type = "desktop"; };
  matrix       = { system = "x86_64-linux";   username = "wenri"; type = "server"; };
  freenix      = { system = "aarch64-linux";  username = "wenri"; type = "server"; };
}

# Plus nix-on-droid (Android) via nixOnDroidConfigurations.default
```

**Features:**
- Auto-generates all `nixosConfigurations` and `homeConfigurations`
- Type-based module loading (wsl, desktop, server)
- Exports overlays, modules, and packages from `common/`
- Integrated home-manager as NixOS module
- Single `nix flake update` updates all hosts

### hosts/ - Per-Host Configurations

Each host has its own directory with minimal configuration:

**wslnix/** (WSL)
- `configuration.nix` - WSL system config, imports from `common/modules/nixos/`
- `users.nix` - WSL-specific user configuration
- `home.nix` - Imports common home-manager modules only

**nixos-gnome/, nixos-plasma6/, irif/** (Desktops)
- `configuration.nix` - Desktop config, imports `common/modules/nixos/users.nix`, `locale.nix`, `secrets.nix`
- `hardware-configuration.nix` - Hardware-specific configuration
- `home.nix` - Imports `core.default` + `desktop.default` + `development`

**matrix/, freenix/** (Servers)
- `configuration.nix` - Server config, imports `common/modules/nixos/server-base.nix`, `users.nix`, `tailscale.nix`
- `facter.json` - nixos-facter hardware detection
- `synapse.nix` (matrix only) - Matrix Synapse server configuration
- `home.nix` - Imports common home-manager modules only

**nix-on-droid/** (Android)
- `configuration.nix` - Nix-on-droid system config with environment.packages and home-manager integration
- `home.nix` - Home-manager config with zsh, git, fzf, claude-code, development tools
- Uses advanced nix-on-droid template pattern with `home-manager-path = home-manager.outPath`
- Master home-manager branch for latest features

## Common Development Commands

### Flake Management
```bash
# Update all flake inputs to latest versions
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs

# Show flake metadata
nix flake show

# Check flake for errors
nix flake check
```

### NixOS System Configuration

**IMPORTANT:** Always use the `--sudo` flag instead of running nixos-rebuild with `sudo`. Additionally, in zsh (the default shell), you **must quote** flake references containing `#` because zsh treats `#` as a special glob character.

```bash
# Apply system configuration for servers
nixos-rebuild switch --sudo --flake '.#matrix'
nixos-rebuild switch --sudo --flake '.#freenix'

# Apply for desktops
nixos-rebuild switch --sudo --flake '.#nixos-gnome'
nixos-rebuild switch --sudo --flake '.#nixos-plasma6'
nixos-rebuild switch --sudo --flake '.#irif'

# Apply for WSL
nixos-rebuild switch --sudo --flake '.#wslnix'

# Test without switching (dry run)
nixos-rebuild test --sudo --flake '.#hostname'

# Build without activating
nixos-rebuild build --sudo --flake '.#hostname'
```

**Why quote flake references in zsh?**

```bash
# ❌ WRONG in zsh - will fail with "no matches found"
nixos-rebuild switch --sudo --flake .#wslnix

# ✅ CORRECT in zsh - quote the flake reference
nixos-rebuild switch --sudo --flake '.#wslnix'

# ✅ Also works - double quotes
nixos-rebuild switch --sudo --flake ".#wslnix"
```

This issue only affects zsh. In bash, `#` starts a comment only at the beginning of a word, so `.#wslnix` works without quotes.

### Nix-on-Droid (Android)
```bash
# Apply nix-on-droid configuration
nix-on-droid switch --flake ~/.config/nix-on-droid

# Or with explicit path
nix-on-droid switch --flake /path/to/config
```

### Home Manager

**Home-manager is now integrated into NixOS configurations.**
A single `nixos-rebuild switch` command updates both system and user environment.

```bash
# Single command updates both NixOS and home-manager
nixos-rebuild switch --sudo --flake '.#matrix'
nixos-rebuild switch --sudo --flake '.#wslnix'

# Standalone home-manager still available for backward compatibility
home-manager switch --flake '.#wenri@matrix'
home-manager switch --flake '.#wenri@freenix'
home-manager switch --flake '.#wenri@wslnix'
home-manager switch --flake '.#wenri@nixos-gnome'
```

### Building Custom Packages
```bash
# Build custom package from common/pkgs/ (exported by the unified flake)
nix build '.#package-name'

# Enter development shell with package
nix shell '.#package-name'

# Example: building the example-package
nix build '.#example-package'
```

### Formatting
```bash
# Format all Nix files (uses alejandra)
nix fmt
```

## Key Architecture Details

### Modern Flake Architecture (2025)

The unified flake follows a modernized architecture:

**Single Source of Truth:**
- `hosts` attribute set in root `flake.nix` defines all 6 system configurations
- Auto-generates `nixosConfigurations` and `homeConfigurations` using `lib.mapAttrs`
- Eliminates redundant declarations and reduces code duplication

**Proper Package Structure:**
- Uses `mkPkgs` helper function for creating package sets
- Packages output uses `forAllSystems` for proper cross-platform support
- Formatter output configured for `nix fmt` using alejandra

**Home-Manager Integration:**
- Integrated as NixOS module (not standalone)
- Uses `home-manager.useGlobalPkgs` and `home-manager.useUserPackages`
- Single command updates both system and user environment
- Backward compatible standalone configurations still available

**Variable System:**
- Per-host username configuration in `hosts` attribute
- `hostname` and `username` passed through `specialArgs` to all modules
- Automatic derivation of paths (e.g., facter files from hostname)

### Host Type Features

**Nix-on-Droid (Android):**
- Uses nix-community/nix-on-droid for Android/Termux environment
- **Custom Android-patched glibc 2.40** with Termux patches for kernel compatibility
- **patchelf-based binary rewriting** to use Android glibc while preserving binary cache
- **Fakechroot login system** with modified fakechroot for proper login shell support (argv[0] handling)
- Modular configuration: base, android-integration, sshd, locale, shizuku
- Home-manager integration via `home-manager.config = ./home.nix`
- SSH server with auto-start via Termux:Boot
- Shizuku integration for `rish` shell access
- Shared packages from `common/packages.nix` (not home-manager)
- `self.submodules = true` for git submodule support
- See `docs/NIX-ON-DROID.md` for detailed configuration guide
- See `docs/ANDROID-GLIBC.md` for Android glibc and Termux patches
- See `docs/FAKECHROOT.md` for libfakechroot modifications

**WSL (wslnix):**
- NixOS-WSL integration for Windows development
- Tailscale with userspace networking
- Dynamic username support

**Desktop (nixos-gnome, nixos-plasma6, irif):**
- GNOME and Plasma6 desktop environments
- ZFS support with LUKS encryption
- VMware guest tools integration
- Full GUI applications and development environments
- Input method: fcitx5 with Rime (using modified fcitx5-rime-lua from common overlays)

**Server (matrix, freenix):**
- Uses **nixos-facter** for hardware detection instead of traditional `hardware-configuration.nix`
- Employs **disko** for declarative disk partitioning
- Configured for remote deployment via **nixos-anywhere**
- Tailscale VPN with network optimization
- System features: Docker, fail2ban, openssh, Matrix Synapse (matrix only)
- Multi-architecture support: x86_64-linux and aarch64-linux
- Swap: Both file-based swap (2GB) and zram (30% of RAM with zstd compression)
- System tools: ethtool, usbutils (lsusb), curl, git, vim, wget, jq
- Passwordless sudo enabled for wheel group
- systemd-oomd enabled for OOM protection

### Flake Input Pattern
All configurations follow the pattern:
```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  nixpkgs-master.url = "github:nixos/nixpkgs/master";
  home-manager.url = "github:nix-community/home-manager";
  home-manager.inputs.nixpkgs.follows = "nixpkgs";
  nur.url = "github:nix-community/NUR";
  nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
}
```
The `follows` ensures home-manager uses the same nixpkgs revision as the system, avoiding version conflicts. NUR provides Firefox extensions and Coq packages, while nix-vscode-extensions provides VS Code marketplace extensions.

### Special Args Pattern
Configurations pass `inputs` and `outputs` to modules via `specialArgs`:
```nix
specialArgs = {inherit inputs outputs;};
```
This makes flake inputs and outputs accessible in all imported modules.

### Module System and Overlays
**Unified Infrastructure in `common/`:**
- Custom modules go in `common/modules/nixos/` (system) or `common/modules/home-manager/` (user)
- Modules must be registered in respective `default.nix` files
- Overlays in `common/overlays/default.nix` provide:
  - `additions` - Custom packages from `common/pkgs/`
  - `modifications` - Package modifications (e.g., fcitx5-rime-lua with Lua support, claude-code path fix)
  - `unstable-packages` - Access to nixpkgs-unstable via `pkgs.unstable.*`
  - `master-packages` - Access to nixpkgs-master via `pkgs.master.*`
  - NUR overlay for Firefox extensions and community packages
  - nix-vscode-extensions overlay for VS Code marketplace extensions

**Overlay Parameters:**
- `inputs` - Flake inputs (required)
- `lib` - nixpkgs lib (defaults to `inputs.nixpkgs.lib`)
- `installationDir` - Android installation directory for path translation (optional, Android-only)

**The unified flake exports from common:**
```nix
overlays = import ./common/overlays {inherit inputs;};
nixosModules = import ./common/modules/nixos;
homeModules = import ./common/modules/home-manager;
packages = forAllSystems (system: import ./common/pkgs {pkgs = mkPkgs system;});
```

**Android-specific overlays** pass `installationDir` for Node.js path translation:
```nix
androidOverlays = import ./common/overlays { inherit inputs installationDir; };
```

### Home Manager Integration
**Fully integrated into NixOS as a module:**
- Added `inputs.home-manager.nixosModules.home-manager` in `mkNixosSystem`
- Configured `home-manager.users.${username} = import ./home-manager/home.nix;`
- Enabled `home-manager.useGlobalPkgs = true` for shared package set
- Enabled `home-manager.useUserPackages = true` for per-user packages
- Single `nixos-rebuild switch` updates both system and user environment
- Standalone `homeConfigurations` still available for backward compatibility

### Important Configuration Details

#### Server host configurations (matrix, freenix)
- Disables global flake registry and channels (opinionated pure flake setup)
- Maps flake inputs to nix registry and NIX_PATH for compatibility
- Uses facter.reportPath from `facter.json` for hardware configuration
- Tailscale routing features enabled (can act as subnet router)
- Network optimization for Tailscale (rx-udp-gro-forwarding)

#### Desktop host configurations (nixos-gnome, nixos-plasma6, irif)
- Traditional `hardware-configuration.nix` for hardware detection
- ZFS with LUKS encryption support
- Desktop environment specific settings (GNOME, Plasma6)
- VMware guest tools integration

#### WSL host configuration (wslnix)
- NixOS-WSL specific integration
- Tailscale userspace networking mode
- Dynamic username support

#### Home-manager configurations
- nixpkgs config inherited from system (when using `useGlobalPkgs`)
- Home state version: 25.05
- User environment reloads systemd units on switch (`sd-switch`)
- Accepts `username` and `hostname` parameters from NixOS
- Core modules auto-imported from `common/home-manager/default.nix`
- Desktop-specific modules imported explicitly in desktop hosts

### Example: Modernized Flake Structure

**Adding a new host** is now as simple as adding one entry to the `hosts` attribute:

```nix
# In flake.nix
hosts = {
  freenix = { system = "aarch64-linux"; username = "wenri"; type = "server"; };
  matrix = { system = "x86_64-linux"; username = "wenri"; type = "server"; };
  newhost = { system = "x86_64-linux"; username = "wenri"; type = "server"; };  # ← Add this
};
```

This automatically generates:
- `nixosConfigurations.newhost`
- `homeConfigurations."wenri@newhost"`
- All necessary specialArgs and module imports
- Type-based module loading (wsl, desktop, or server)

**Helper functions** reduce boilerplate:
```nix
mkNixosSystem = { hostname, system, username, type }: ...
mkHomeConfiguration = { hostname, system, username }: ...
mkPkgs = system: import nixpkgs { inherit system; config.allowUnfree = true; };
```

**Benefits:**
- DRY principle: No duplicate hostname/system/username declarations
- Type safety: Impossible to mismatch system architectures or usernames
- Maintainability: Single source of truth for all 6 hosts
- Consistency: Same pattern across all host types (wsl, desktop, server)

## Git Workflow
Files must be tracked by git for Nix flakes to see them:
```bash
git add .  # Flakes only see tracked files
```
Files in `.gitignore` are invisible to Nix evaluations.

## Deployment with nixos-anywhere
For fresh installations of server hosts:
```bash
# With nixos-facter hardware detection
# Pattern: nixos-anywhere --flake '.#<hostname>' --generate-hardware-config nixos-facter ./hosts/<hostname>/facter.json <target>

# For matrix (x86_64-linux)
nixos-anywhere --flake '.#matrix' \
  --generate-hardware-config nixos-facter ./hosts/matrix/facter.json \
  root@target-host

# For freenix (aarch64-linux)
nixos-anywhere --flake '.#freenix' \
  --generate-hardware-config nixos-facter ./hosts/freenix/facter.json \
  root@target-host
```

## Important Notes
- **Single unified flake**: All 6 NixOS hosts + 1 nix-on-droid managed by root `flake.nix`
- **Unified infrastructure**: All hosts share infrastructure from `common/` (overlays, modules, packages)
- **Unified userspace**: All users are the same person: Bingchen Gong (username: wenri)
- **All home-manager configuration identical**: Same packages, programs, and dotfiles across all environments
- System state version: 25.05
- Home state version: 25.05 (24.05 for nix-on-droid)
- Custom packages accessible via `nix build '.#package-name'`
- Firefox extensions from NUR (1Password, uBlock Origin, Translate Web Pages)
- VS Code extensions from nix-vscode-extensions marketplace overlay
- Coq packages from NUR (lngen, ott-sweirich)
- Formatter set to `alejandra` - use `nix fmt` to format all Nix files

## Documentation Structure

```
docs/
├── NIX-ON-DROID.md        # Overview: installation, configuration, architecture, usage
├── ANDROID-GLIBC.md       # Android glibc: Termux patches, ld.so path translation, build
├── FAKECHROOT.md          # libfakechroot: modifications, integration, troubleshooting
└── SECCOMP.md             # Seccomp capabilities, USER_NOTIF supervisor, static binary handling

scripts/seccomp/           # Seccomp utilities for static binaries
├── seccomp-wrapper.c      # Wrapper returning ENOSYS for blocked syscalls
└── seccomp-supervisor-demo.c  # USER_NOTIF supervisor demo

CLAUDE.md                  # This file - AI assistant guidance (root level)
README.md                  # Project README
```

### Key Documentation Topics

| Document | Topics Covered |
|----------|---------------|
| **NIX-ON-DROID.md** | Architecture overview, installation, module structure, services (SSH, Shizuku) |
| **ANDROID-GLIBC.md** | Android seccomp, Termux patches, ld.so built-in path translation, building glibc |
| **FAKECHROOT.md** | libfakechroot as LD_PRELOAD library, argv[0] fix, readlink buffer overflow fix |
| **SECCOMP.md** | Seccomp features on Android, USER_NOTIF supervisor, handling static binaries |

## Android-Specific (nix-on-droid)

### Key Concepts

1. **Android glibc**: Standard glibc won't work on Android due to seccomp-blocked syscalls (clone3, set_robust_list, rseq)
2. **Termux Patches**: Community-maintained patches that disable/workaround blocked syscalls
3. **NixOS-style Grafting**: Uses patchnar for recursive dependency patching with hash mapping
4. **patchnar**: NAR stream patcher that modifies ELF interpreters/RPATH, symlinks, and scripts
5. **Binary Cache**: Most packages still come from nixpkgs binary cache (patched at install time)
6. **Fakechroot Login**: Uses fakechroot instead of proot for better performance
7. **Go Binary Exceptions**: Go binaries cannot be patched with patchelf (see below)

### NixOS-style Grafting with patchnar

The `build.replaceAndroidDependencies` function implements NixOS-style recursive grafting for Android:

**How it works:**
1. Uses IFD (Import From Derivation) with `exportReferencesGraph` to discover full dependency closure
2. Creates a fixed-point memo that recursively patches each package
3. patchnar processes NAR streams, modifying ELF binaries, symlinks, and scripts
4. Hash mapping substitutes old store path hashes with new patched ones
5. Only glibc is a cutoff package (replaced with Android glibc, not patched)

**What patchnar patches:**
- **ELF interpreters**: `/nix/store/xxx-glibc-2.40/lib/ld-linux.so` → `$PREFIX/nix/store/yyy-glibc-android-2.40/lib/ld-linux.so`
- **ELF RPATH**: Adds prefix, substitutes glibc paths, applies hash mapping
- **Symlinks**: Adds prefix to `/nix/store/` targets, applies hash mapping
- **Script shebangs**: Adds prefix, substitutes glibc paths, applies hash mapping
- **Inter-package references**: Hash mapping ensures all store path references are updated

**Key files:**
- `common/modules/android/replace-android-dependencies.nix` - IFD-based grafting
- `common/modules/android/android-integration.nix` - Wires up replaceAndroidDependencies
- `submodules/patchnar/src/patchnar.cc` - NAR stream patcher

### nix-ld Integration

nix-ld provides a shim at a short path that redirects to the real dynamic linker via environment variables. This solves patchelf issues with Go binaries.

**How it works:**
1. nix-ld shim installed at `$PREFIX/lib/ld-linux-aarch64.so.1` (61 chars)
2. All binaries patched to use this short interpreter path (< original 83 chars)
3. `NIX_LD` points to real Android glibc ld.so
4. `NIX_LD_LIBRARY_PATH` provides library search paths

**Why this matters:**
- patchelf can corrupt binaries when restructuring ELF headers (changing interpreter or adding RPATH)
- With nix-ld, interpreter path is shorter than original (61 < 83 chars), so no restructuring needed
- Binaries with no original RPATH skip RPATH patching (rely on NIX_LD_LIBRARY_PATH instead)
- This fixes Go binaries which typically have no RPATH

**Environment variables** (set in `environment.sessionVariables`):
- `NIX_LD`: Path to Android glibc's `ld-linux-aarch64.so.1`
- `NIX_LD_LIBRARY_PATH`: Android glibc + gcc-lib paths
- `SSL_CERT_FILE` / `SSL_CERT_DIR`: Real nix store paths for SSL certs
- `GODEBUG=netdns=cgo`: Forces Go to use glibc DNS resolver

**Current status:**
- **gh** works with nix-ld
- **glab** works with SIGSYS handler + sigaction wrapper (intercepts blocked faccessat2, returns ENOSYS)

### Fakechroot Login System

The `/bin/login` script is auto-generated by nix-on-droid with fakechroot support:

**Components built by flake.nix:**
- `androidFakechroot` - Fakechroot with Android glibc RPATH (modified for login shell support)
- `packAuditLib` - pack-audit.so for `/nix/store` path rewriting

**Build options in submodules/nix-on-droid/modules/build/config.nix:**
- `build.androidGlibc` - Android-patched glibc package
- `build.standardGlibc` - Standard glibc for path redirection
- `build.androidFakechroot` - Android-patched fakechroot (with argv[0] fix)
- `build.packAuditLib` - Path to pack-audit.so
- `build.bashInteractive` - Bash for login shell

**Fakechroot Modifications:**
The fakechroot source in `submodules/fakechroot/` has been modified for nix-on-droid:
- **argv[0] Fix**: Uses original `argv[0]` (e.g., `-zsh`) for `ld.so --argv0` instead of executable path
- **Argument Skipping**: Skips `argv[0]` when copying arguments if `--argv0` is used
- **Login Shell Support**: Ensures shells correctly detect login status without parsing `-z` as invalid option
- **SIGSYS Handler**: Intercepts seccomp-blocked syscalls (faccessat2) and returns ENOSYS for fallback
- **sigaction Wrapper**: Prevents Go runtime from overriding SIGSYS handler, enabling Go binaries (glab, etc.)
- Modified files: `submodules/fakechroot/src/execve.c`, `posix_spawn.c`, `libfakechroot.c`, `sigaction.c`

**Debug hook:** Edit `~/.config/nix-on-droid/login-debug.sh` to customize login without rebuilding.

### File Locations

```
submodules/                             # Git submodules for external dependencies
├── fakechroot/                         # Android-patched fakechroot (from Wenri/fakechroot)
│   └── src/execve.c, posix_spawn.c    # Modified for login shell argv[0] handling
│   └── src/libfakechroot.c            # SIGSYS handler for seccomp bypass
│   └── src/sigaction.c                # sigaction wrapper for Go compatibility
├── glibc/                              # GNU C Library source (from Wenri/glibc)
│                                        # Tracking release/2.40/master branch
│                                        # Patches applied at build time from patches/glibc-termux/
├── patchnar/                           # NAR stream patcher (from Wenri/patchnar)
│                                        # Patches ELF, symlinks, scripts within NAR streams
│                                        # Uses patchelf library for ELF modifications
├── nix-on-droid/                       # nix-on-droid source (from Wenri/nix-on-droid fork)
│   └── modules/                        # nix-on-droid modules and build config
└── secrets/                            # Secrets repository (from GitLab)
    └── tailscale-auth.key              # Tailscale authentication key

common/overlays/
├── additions.nix                       # Custom packages overlay
├── channels.nix                        # nixpkgs-unstable and nixpkgs-master channels
├── default.nix                         # Overlay entry point
└── modifications.nix                   # Package modifications (claude-code, etc.)

common/pkgs/
├── android-fakechroot.nix              # Android-patched fakechroot
├── android-glibc.nix                   # Android-patched glibc 2.40
├── patchnar.nix                        # NAR stream patcher (uses patchelf for ELF)
├── rish.nix                            # Shizuku rish shell for Android
├── default.nix                         # Package set entry point
└── glibc-termux/                       # 28 patch files + source files for glibc

common/modules/android/
├── default.nix                         # Module exports
├── base.nix                            # Core packages, nix settings
├── android-integration.nix             # NixOS-style grafting with patchnar, Termux tools
├── replace-android-dependencies.nix    # IFD-based recursive dependency patching
├── sshd.nix                            # SSH server
├── locale.nix                          # Timezone/locale
└── shizuku.nix                         # Shizuku rish shell

scripts/
├── pack-audit.c                        # Source for pack-audit.so (built by Nix)
└── login-proot                         # Original proot login for reference

submodules/nix-on-droid/modules/
├── build/config.nix                    # Build options for fakechroot
└── environment/login/login.nix         # Fakechroot login script generator

common/packages.nix                     # Shared package lists for nix-on-droid

hosts/nix-on-droid/
├── configuration.nix                   # System config (imports modules)
└── home.nix                            # Home-manager config

login-debug.sh                          # User-modifiable debug hook for /bin/login
```

### nix-on-droid Commands

```bash
# Apply configuration
nix-on-droid switch --flake ~/.config/nix-on-droid

# Build without switching
nix-on-droid build --flake .

# Rollback to previous generation
nix-on-droid rollback

# List generations
nix-on-droid list-generations

# Build Android glibc separately
nix build .#androidGlibc

# Build fakechroot separately
nix build .#androidFakechroot
```

### Flake Outputs for Android

```nix
# Available outputs for aarch64-linux
packages.aarch64-linux.androidGlibc           # Android-patched glibc 2.40
packages.aarch64-linux.androidFakechroot      # Android-patched fakechroot
packages.aarch64-linux.patchnar               # NAR stream patcher
packages.aarch64-linux.rish                   # Shizuku rish shell
lib.aarch64-linux.androidGlibc                # Same, via lib output

# nix-on-droid configurations
nixOnDroidConfigurations.default              # Main config
nixOnDroidConfigurations.nix-on-droid         # Named config
```
