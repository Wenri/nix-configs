# Packages and Home-Manager Modules Reference

This document describes all custom packages in `common/pkgs/` and home-manager modules in `common/modules/home-manager/`.

## Custom Packages (`common/pkgs/`)

### Entry Point: `common/pkgs/default.nix`

The package set is exported via the flake and can be built with:
```bash
nix build '.#packageName'
```

### androidGlibc (`android-glibc.nix`)

**Description**: Android-patched glibc 2.40 with Termux patches for Android seccomp compatibility.

**Key Features**:
- Disables syscalls blocked by Android seccomp (clone3, set_robust_list, rseq)
- Pre-patched source from `submodules/glibc` with both nixpkgs and Termux patches
- Generates `android_ids.h` for Android user/group ID mapping
- Processes `fakesyscall.json` to generate `disabled-syscall.h`
- Single-output build to avoid multi-output issues on Android
- Built-in path translation for `/nix/store` -> Android prefix

**Build Command**:
```bash
nix build '.#androidGlibc'
```

### androidFakechroot (`android-fakechroot.nix`)

**Description**: Android-patched fakechroot with compile-time hardcoded paths and SIGSYS handler.

**Key Features**:
- Compile-time configuration via `AC_ARG_VAR` (no environment fallback)
- RPATH patched to use Android glibc
- Excludes Android system paths from chroot translation
- SIGSYS handler intercepts seccomp-blocked syscalls (faccessat2)
- sigaction wrapper prevents Go runtime from overriding SIGSYS handler

**Required Parameters**:
- `androidGlibc` - Android-patched glibc package
- `installationDir` - Base installation directory
- `src` - Path to fakechroot source

**Build Command**:
```bash
nix build '.#androidFakechroot'
```

### patchnar (`patchnar.nix`)

**Description**: NAR stream patcher for Android compatibility, based on patchelf.

**Key Features**:
- Patches ELF binaries within NAR streams (interpreter, RPATH)
- Patches symlinks to add Android prefix
- Patches script shebangs
- Applies hash mapping for recursive dependency patching
- Includes full patchelf functionality

**Build Command**:
```bash
nix build '.#patchnar'
```

### rish (`rish.nix`)

**Description**: Shizuku shell for privileged Android commands.

**Key Features**:
- Extracts `rish_shizuku.dex` from Shizuku APK
- Runs via `/system/bin/app_process` with Java classpath
- Requires Shizuku app to be running with ADB or root authorization
- Enables privileged shell access without root

**Build Command**:
```bash
nix build '.#rish'
```

---

## Home-Manager Modules (`common/modules/home-manager/`)

### Module Export Structure

```nix
homeModules = {
  core = {
    default   # Full core module (all imports)
    packages  # CLI tools and programs
    programs  # Base program enables
    git       # Git configuration
    zsh       # Zsh configuration
    ssh       # SSH configuration
    gh        # GitHub CLI configuration
  };
  desktop = {
    default   # Full desktop module (all imports)
    packages  # GUI applications
  };
  development = {
    default   # Core dev packages (works everywhere)
    full      # Full dev (texlive + coq, needs NUR)
  };
};
```

### Usage Examples

**Desktop hosts** (NUR available):
```nix
imports = [
  outputs.homeModules.core.default
  outputs.homeModules.desktop.default
  outputs.homeModules.development.full
];
```

**WSL/Android hosts** (no texlive/NUR):
```nix
imports = [
  outputs.homeModules.core.default
  outputs.homeModules.development.default
];
```

---

## Core Modules (`core/`)

### core.default (`core/default.nix`)

Imports all core modules: packages, git, zsh, ssh, gh, programs.

### core.packages (`core/packages.nix`)

**CLI Tools**:
| Package | Description |
|---------|-------------|
| parted | Disk partition management |
| iperf3 | Network bandwidth testing |
| nodejs | JavaScript runtime |
| glab | GitLab CLI |
| claude-code | Claude AI CLI |
| cursor-cli | Cursor AI CLI |
| gemini-cli | Google Gemini CLI |
| github-copilot-cli | GitHub Copilot CLI |

**Programs Enabled**:
- `fzf` with Zsh integration

### core.programs (`core/programs.nix`)

| Program | Status |
|---------|--------|
| home-manager | Enabled |
| tmux | Enabled |
| vim | Package installed |

### core.git (`core/git.nix`)

**Configuration**:
- User: Bingchen Gong
- Email: 6704443+Wenri@users.noreply.github.com
- Default branch: main
- Submodule recursion: enabled
- GitLab credential helper via `glab auth git-credential`

**Helper Scripts**:
- `glab-netrc-sync` - Syncs GitLab credentials to ~/.netrc for Nix
- `git` wrapper - Pre-fetch hook for GitLab authentication

### core.zsh (`core/zsh.nix`)

**Configuration**:
- Oh-My-Zsh with `git` plugin
- Theme: robbyrussell
- Autosuggestion enabled
- Syntax highlighting enabled
- History: 10000 entries in `~/.local/share/zsh/history`

**Aliases**:
- `ll` = `ls -l`

### core.ssh (`core/ssh.nix`)

**Match Blocks**:
- `github.com` - Uses `ssh.github.com:443` (firewall-friendly)
- `*` - Adds keys to agent automatically

### core.gh (`core/gh.nix`)

**Configuration**:
- GitHub CLI enabled
- Git credential helper enabled

---

## Desktop Modules (`desktop/`)

### desktop.default (`desktop/default.nix`)

Imports: packages, rime, vscode, emacs, firefox, gnome, pcloud.

### desktop.packages (`desktop/packages.nix`)

**Communication**:
| Package | Description |
|---------|-------------|
| element-desktop | Matrix client |
| discord | Discord client |
| slack | Slack client |
| signal-desktop | Signal messenger |

**Collaboration**:
| Package | Description |
|---------|-------------|
| zoom-us | Video conferencing |
| teamviewer | Remote desktop |

**Productivity**:
| Package | Description |
|---------|-------------|
| siyuan | Note-taking app |
| bitwarden-desktop | Password manager |
| parsec-bin | Low-latency game streaming |

**Browsers**:
| Package | Description |
|---------|-------------|
| google-chrome | Chrome browser |

**Social**:
| Package | Description |
|---------|-------------|
| wechat-uos | WeChat for Linux |

### desktop.emacs (`desktop/emacs.nix`)

**Configuration**:
- Package: `emacs-pgtk` (pure GTK)
- Standard indent: 2

### desktop.firefox (`desktop/firefox/default.nix`)

**Extensions** (from NUR):
- 1Password Password Manager
- Translate Web Pages
- uBlock Origin

**Settings**:
- DRM enabled (Widevine)
- Pocket disabled
- Dark mode
- Picture-in-Picture always visible
- Built-in password manager disabled (use 1Password)

### desktop.vscode (`desktop/vscode/default.nix`)

**Extensions** (from vscode-marketplace):
| Extension | Description |
|-----------|-------------|
| akamud.vscode-theme-onedark | One Dark theme |
| akamud.vscode-theme-onelight | One Light theme |
| coq-community.vscoq1 | Coq IDE |
| eamodio.gitlens | Git lens |
| github.copilot | GitHub Copilot |
| github.copilot-chat | Copilot Chat |
| github.vscode-pull-request-github | GitHub PRs |
| haskell.haskell | Haskell support |
| james-yu.latex-workshop | LaTeX IDE |
| jnoortheen.nix-ide | Nix language support |
| justusadam.language-haskell | Haskell syntax |
| mgt19937.typst-preview | Typst preview |
| myriad-dreamin.tinymist | Typst LSP |
| richie5um2.vscode-sort-json | JSON sorter |
| skellock.just | Justfile support |
| vscode-icons-team.vscode-icons | File icons |
| yellpika.latex-input | LaTeX input |

### desktop.rime (`desktop/rime/default.nix`)

**Configuration**:
- Installs rime-ice (Chinese input) to `~/.local/share/fcitx5/rime`

### desktop.gnome (`desktop/gnome.nix`)

**Extensions**:
- kimpanel - Input method panel for fcitx5

### desktop.pcloud (`desktop/pcloud.nix`)

**Configuration**:
- Uses patched patchelf to fix pcloud binary
- Patches from Patryk27/patchelf fork

---

## Development Modules (`development/`)

### development.default (`development/default.nix`)

Core development packages that work on all platforms (no texlive, no NUR dependencies).

Imports: packages.nix only.

### development.full (`development/full.nix`)

Full development environment for desktop hosts. Requires NUR.

Imports: packages.nix + coq.nix + texlive.

### development/packages.nix

**Python**:
| Package | Description |
|---------|-------------|
| python3 + requests | Python environment |

**Haskell**:
| Package | Description |
|---------|-------------|
| ghc | Glasgow Haskell Compiler |
| stack | Haskell build tool |
| cabal-install | Cabal build tool |
| haskell-language-server | Haskell LSP |

**Rust**:
| Package | Description |
|---------|-------------|
| rustc | Rust compiler |
| cargo | Rust package manager |
| rust-analyzer | Rust LSP |
| clippy | Rust linter |
| rustfmt | Rust formatter |

**Go**:
| Package | Description |
|---------|-------------|
| go | Go compiler |
| gopls | Go LSP |
| delve | Go debugger |
| go-tools | Go development tools |

**Other Languages**:
| Package | Description |
|---------|-------------|
| agda | Dependently-typed language |
| elixir | Functional language on BEAM |
| octave | GNU Octave (MATLAB-compatible) |
| typst | Modern typesetting system |
| tinymist | Typst LSP |

### development.full extras

**LaTeX** (only in `full`):
| Package | Description |
|---------|-------------|
| texlive.combined.scheme-full | Full TeX Live |
| python3Packages.pygments | Code highlighting |

### development/coq.nix (only in `full`)

**Requires NUR** - Only available via `development.full`.

**Packages** (from NUR chen repo):
| Package | Description |
|---------|-------------|
| coq | Coq proof assistant (8.19) |
| lngen | Locally nameless generator |
| ott-sweirich | Ott semantics tool |

**Environment**:
- `COQPATH` set to `~/.nix-profile/lib/coq/8.19/user-contrib`

---

## Host Configuration Reference

### Per-Host Module Imports

| Host | core.default | desktop.default | development.default | development.full |
|------|:------------:|:---------------:|:-------------------:|:----------------:|
| **nixos-gnome** | ✓ | ✓ | | ✓ |
| **nixos-plasma6** | ✓ | ✓ | | ✓ |
| **irif** | ✓ | ✓ | | ✓ |
| **wslnix** | ✓ | | ✓ | |
| **nix-on-droid** | ✓ | | ✓ | |
| **matrix** | ✓ | | ✓ | |
| **freenix** | ✓ | | | |

### Why the Split?

| Module | texlive | coq (NUR) | Works on Android | Works on WSL |
|--------|:-------:|:---------:|:----------------:|:------------:|
| `development.default` | | | ✓ | ✓ |
| `development.full` | ✓ | ✓ | | ✓* |

*WSL can technically use `development.full` but it's not configured to do so.

**Reasons for the split:**
- **texlive** can't build on Android due to `faketime` failing with seccomp restrictions
- **coq.nix** requires NUR packages which are not set up on Android/WSL
- `development.default` provides all language toolchains (Rust, Go, Haskell, Python, etc.) without these dependencies
