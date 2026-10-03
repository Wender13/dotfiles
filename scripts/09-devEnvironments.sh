#!/bin/bash
# MENU_DESC: Dev tools: Rust, uv, Node, Tauri, Claude
# CATEGORY: DEVELOPMENT
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro

ensure_command curl curl curl
ensure_command unzip unzip unzip   # required by the fnm installer

# ─── Build / Tauri Dependencies ───────────────────────────────────────────────
# First, so that anything compiled below (cargo, native npm modules) finds a C toolchain.
print_header "Installing build and Tauri system dependencies"
if is_apt; then
    sudo apt-get update
    sudo apt-get install -y \
        libwebkit2gtk-4.1-dev \
        build-essential \
        curl \
        wget \
        file \
        libxdo-dev \
        libssl-dev \
        libayatana-appindicator3-dev \
        librsvg2-dev
elif is_dnf; then
    sudo dnf install -y \
        webkit2gtk4.1-devel \
        openssl-devel \
        curl \
        wget \
        file \
        libappindicator-gtk3-devel \
        librsvg2-devel \
        libxdo-devel \
        @c-development
fi

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
        sudo dnf install -y rustup
        rustup-init -y --no-modify-path
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    fi
    source "$HOME/.cargo/env"
else
    echo -e "${C_YELLOW}Rust is already installed.${C_RESET}"
fi

# ─── Eza (Modern ls) ──────────────────────────────────────────────────────────
if ! command -v eza &>/dev/null; then
    echo -e "${C_BLUE}Installing eza...${C_RESET}"
    if is_dnf; then
        sudo dnf install -y eza
    else
        cargo install --locked eza
    fi
else
    echo -e "${C_YELLOW}eza is already installed.${C_RESET}"
fi

# ─── Python (uv) ──────────────────────────────────────────────────────────────
print_header "Setting up Python (uv)"
if ! command -v uv &>/dev/null; then
    echo -e "${C_BLUE}Installing uv (Modern Python package manager)...${C_RESET}"
    if is_dnf; then
        sudo dnf install -y uv
    else
        curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
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
# A default version that already exists (chosen by the user) is kept as is.
if fnm list | grep -E '(^|[ ,])default(,|$)' > /dev/null; then
    echo -e "${C_YELLOW}fnm already has a default Node.js version. Keeping it.${C_RESET}"
else
    echo -e "${C_BLUE}Installing Node.js (latest LTS)...${C_RESET}"
    fnm install --lts
    fnm default lts-latest
fi
fnm use default

if ! command -v pnpm &>/dev/null; then
    echo -e "${C_BLUE}Installing pnpm...${C_RESET}"
    npm install -g pnpm
else
    echo -e "${C_YELLOW}pnpm is already installed.${C_RESET}"
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
    echo -e "${C_YELLOW}Claude Code is already installed.${C_RESET}"
fi

echo -e "${C_GREEN}Dev environments (Rust/Tauri/Python/Node/Claude Code) installed!${C_RESET}"
