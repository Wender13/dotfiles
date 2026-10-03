#!/bin/bash
# MENU_DESC: Dev tools: Rust, Node, uv, Tauri, AI CLIs
# CATEGORY: DEVELOPMENT
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro

ensure_command curl curl curl
ensure_command unzip unzip unzip   # required by the fnm installer

# Packages installed here; installed ones with a newer version are offered at the end in a
# single question. Languages (Rust, Node, pnpm, uv) are asked one by one, since changing
# their version is what most often breaks projects. See the update policy in lib.sh.
OFFER=()

# ─── Build / Tauri Dependencies ───────────────────────────────────────────────
# First, so that anything compiled below (cargo, native npm modules) finds a C toolchain.
print_header "Installing build and Tauri system dependencies"
if is_apt; then
    sudo apt-get update
    PACKAGES=(libwebkit2gtk-4.1-dev build-essential curl wget file libxdo-dev libssl-dev
        libayatana-appindicator3-dev librsvg2-dev)
elif is_dnf; then
    PACKAGES=(webkit2gtk4.1-devel openssl-devel curl wget file libappindicator-gtk3-devel
        librsvg2-devel libxdo-devel @c-development)
fi
install_missing_packages "${PACKAGES[@]}"
OFFER+=("${PACKAGES[@]}")

# ─── Rust & Cargo ─────────────────────────────────────────────────────────────
print_header "Setting up Rust (rustup)"
# A previous install may not be on the PATH of this non-interactive shell yet
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi

if ! command -v cargo &>/dev/null; then
    echo -e "${C_BLUE}Installing Rust and Cargo...${C_RESET}"
    # --no-modify-path: the repo .zshrc already loads ~/.cargo/env
    if is_dnf; then
        install_missing_packages rustup
        rustup-init -y --no-modify-path
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    fi
    source "$HOME/.cargo/env"
elif command -v rustup &>/dev/null; then
    echo -e "${C_YELLOW}Rust is already installed.${C_RESET}"
    # e.g. "stable-x86_64-unknown-linux-gnu - update available: 1.98.1 (...) -> 1.99.0 (...)"
    mapfile -t rust_lines < <(rustup check 2> /dev/null \
        | sed -nE 's/^([^ ]+) - update available: ([^ ]+) .* -> ([^ ]+) .*/\1 \2 -> \3/p')
    if confirm_updates "Rust (toolchain)" "${rust_lines[@]}"; then
        rustup update --no-self-update
    fi
else
    echo -e "${C_YELLOW}Rust is already installed (not managed by rustup).${C_RESET}"
fi
if is_dnf; then
    OFFER+=(rustup)
fi

# ─── Eza (Modern ls) ──────────────────────────────────────────────────────────
# Native package where the distribution has it (Fedora, Ubuntu 24.04+, Debian 13+)
if is_dnf || apt-cache show eza &>/dev/null; then
    install_missing_packages eza
    OFFER+=(eza)
elif ! command -v eza &>/dev/null; then
    echo -e "${C_BLUE}Installing eza (cargo)...${C_RESET}"
    cargo install --locked eza
else
    echo -e "${C_YELLOW}eza is already installed.${C_RESET}"
fi

# ─── Python (uv) ──────────────────────────────────────────────────────────────
print_header "Setting up Python (uv)"
if is_dnf; then
    install_missing_packages uv
    OFFER+=(uv)
elif ! command -v uv &>/dev/null; then
    echo -e "${C_BLUE}Installing uv (Modern Python package manager)...${C_RESET}"
    curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
elif [ "$(command -v uv)" = "$HOME/.local/bin/uv" ]; then
    # Installed by the official installer, so it can update itself
    uv_current="$(uv --version | awk '{ print $2 }')"
    # Version checks never abort the module: offline means "could not check"
    uv_latest="$(curl -fsSI https://github.com/astral-sh/uv/releases/latest | sed -n 's#^location: .*/tag/##ip' | tr -d '\r')" || uv_latest=""
    if [ -n "$uv_latest" ] && version_gt "$uv_latest" "$uv_current" \
        && confirm_updates "uv" "uv $uv_current -> $uv_latest"; then
        uv self update
    fi
else
    echo -e "${C_YELLOW}uv is already installed.${C_RESET}"
fi

# ─── Node.js (fnm) & PNPM ─────────────────────────────────────────────────────
print_header "Setting up Node.js (fnm) and pnpm"
FNM_PATH="$HOME/.local/share/fnm"   # same path the repo .zshrc loads

if ! command -v fnm &>/dev/null && [ ! -x "$FNM_PATH/fnm" ]; then
    echo -e "${C_BLUE}Installing fnm (Fast Node Manager)...${C_RESET}"
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell --install-dir "$FNM_PATH"
else
    echo -e "${C_YELLOW}fnm is already installed.${C_RESET}"
fi

export PATH="$FNM_PATH:$PATH"
eval "$(fnm env --shell bash)"

# Each step is checked on its own, so a rerun completes a previously interrupted setup.
# e.g. "* v24.21.0 default"
node_default="$(fnm list | sed -nE 's/^\* (v[0-9.]+) .*default.*/\1/p' | head -n1)"
if [ -z "$node_default" ]; then
    echo -e "${C_BLUE}Installing Node.js (latest LTS)...${C_RESET}"
    fnm install --lts
    fnm default lts-latest
else
    echo -e "${C_YELLOW}fnm default Node.js version: $node_default${C_RESET}"
    node_lts="$(fnm list-remote --lts | tail -n1 | awk '{ print $1 }')" || node_lts=""
    if [ -n "$node_lts" ] && version_gt "$node_lts" "$node_default" \
        && confirm_updates "Node.js (versao padrao do fnm; pacotes globais do npm ficam na versao anterior)" \
            "node $node_default -> $node_lts (LTS)"; then
        if ! fnm list | grep -qF "$node_lts"; then
            fnm install "$node_lts"
        fi
        fnm default "$node_lts"
    fi
fi
fnm use default

# pnpm: official standalone build, independent of the Node version selected in fnm.
# Its installer always runs 'pnpm setup', which appends to the shell rc file, so it runs
# with a throwaway HOME: the repo .zshrc already exports PNPM_HOME and its PATH.
PNPM_HOME="$HOME/.local/share/pnpm"
export PNPM_HOME
if [ ! -x "$PNPM_HOME/bin/pnpm" ]; then
    echo -e "${C_BLUE}Installing pnpm (standalone)...${C_RESET}"
    throwaway_home="$(mktemp -d)"
    curl -fsSL https://get.pnpm.io/install.sh | env HOME="$throwaway_home" PNPM_HOME="$PNPM_HOME" SHELL=/bin/bash sh -
    rm -rf "$throwaway_home"
else
    echo -e "${C_YELLOW}pnpm is already installed.${C_RESET}"
    pnpm_current="$("$PNPM_HOME/bin/pnpm" --version)"
    pnpm_latest="$(curl -fsS https://registry.npmjs.org/pnpm/latest | sed -nE 's/.*"version":"([^"]+)".*/\1/p')" || pnpm_latest=""
    if [ -n "$pnpm_latest" ] && version_gt "$pnpm_latest" "$pnpm_current" \
        && confirm_updates "pnpm" "pnpm $pnpm_current -> $pnpm_latest"; then
        "$PNPM_HOME/bin/pnpm" self-update
    fi
fi

# ─── Claude Code ──────────────────────────────────────────────────────────────
# Official recommended method (native installer): installs into ~/.local/bin and
# updates itself in the background. It refuses to run under sudo by design.
print_header "Setting up Claude Code"
export PATH="$HOME/.local/bin:$PATH"   # where the launcher lives (already in the repo .zshrc)

if ! command -v claude &>/dev/null; then
    echo -e "${C_BLUE}Installing Claude Code (native installer)...${C_RESET}"
    curl -fsSL https://claude.ai/install.sh | bash
else
    echo -e "${C_YELLOW}Claude Code is already installed (it updates itself in the background).${C_RESET}"
fi

# ─── Antigravity CLI ──────────────────────────────────────────────────────────
# Official installer: the 'agy' binary goes to ~/.local/bin and updates itself. Its last
# step ('agy install') edits shell profiles, so it runs with a throwaway HOME; the repo
# .zshrc already has ~/.local/bin on the PATH.
print_header "Setting up Antigravity CLI"
if ! command -v agy &>/dev/null; then
    echo -e "${C_BLUE}Installing Antigravity CLI (official installer)...${C_RESET}"
    mkdir -p "$HOME/.local/bin"
    throwaway_home="$(mktemp -d)"
    curl -fsSL https://antigravity.google/cli/install.sh | env HOME="$throwaway_home" bash -s -- --dir "$HOME/.local/bin"
    rm -rf "$throwaway_home"
else
    echo -e "${C_YELLOW}Antigravity CLI is already installed (it updates itself in the background).${C_RESET}"
fi

offer_package_upgrades "09 - pacotes de desenvolvimento" "${OFFER[@]}"

echo -e "${C_GREEN}Dev environments (Rust/Tauri/Python/Node/Claude Code/Antigravity) installed!${C_RESET}"
