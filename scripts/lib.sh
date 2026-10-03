#!/bin/bash
# Shared library sourced by every module in scripts/. Not meant to be executed directly.

C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'
C_DIM='\033[2m'

DOTFILES_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")"

# Modules write to $HOME and call sudo only where needed. Running them as root
# would install everything into /root.
if [ "$(id -u)" -eq 0 ]; then
    echo -e "${C_RED}Do not run this as root or with sudo. Use your normal user.${C_RESET}" >&2
    exit 1
fi

print_header() {
    echo -e "\n${C_BLUE}${C_BOLD}=== $1 ===${C_RESET}"
}

error_handler() {
    local exit_code=$1
    local line_no=$2
    local command=$3
    echo -e "\n${C_RED}${C_BOLD}[ERRO CRITICO] Falha na execucao do script!${C_RESET}" >&2
    echo -e "${C_YELLOW}Arquivo:${C_RESET} ${BASH_SOURCE[1]:-$0}" >&2
    echo -e "${C_YELLOW}Linha do erro:${C_RESET} $line_no" >&2
    echo -e "${C_YELLOW}Comando que falhou:${C_RESET} $command (status $exit_code)" >&2
    echo -e "${C_DIM}Dica para a IA: Busque uma solucao alternativa para este pacote/comando e sugira a correcao ao usuario.${C_RESET}\n" >&2
}
# errtrace makes the trap also fire inside functions (e.g. a failing git clone in clone_if_missing).
set -o errtrace
trap 'error_handler $? $LINENO "$BASH_COMMAND"' ERR

detect_distro() {
    if [ ! -f /etc/os-release ]; then
        echo -e "${C_RED}Cannot detect distribution: /etc/os-release not found.${C_RESET}" >&2
        exit 1
    fi

    # shellcheck source=/dev/null
    . /etc/os-release

    local ids=" ${ID:-} ${ID_LIKE:-} "
    if [[ "$ids" == *" rhel "* || "$ids" == *" centos "* ]]; then
        echo -e "${C_RED}Unsupported distribution: ${ID:-unknown}. The dnf modules rely on Fedora-only repositories (RPM Fusion, fedora-workstation-repositories).${C_RESET}" >&2
        exit 1
    elif [[ "$ids" == *" fedora "* ]]; then
        if [ -e /run/ostree-booted ]; then
            echo -e "${C_RED}Fedora Atomic (Silverblue, Kinoite...) is not supported: packages are layered with rpm-ostree, not dnf.${C_RESET}" >&2
            exit 1
        fi
        PKG_MANAGER="dnf"
        if ! command -v dnf5 &>/dev/null; then
            echo -e "${C_RED}Fedora 41+ (dnf5) is required. The modules use dnf5 syntax.${C_RESET}" >&2
            exit 1
        fi
    elif [[ "$ids" == *" debian "* || "$ids" == *" ubuntu "* ]]; then
        PKG_MANAGER="apt"
    else
        echo -e "${C_RED}Unsupported distribution: ${ID:-unknown}${C_RESET}" >&2
        exit 1
    fi
}

is_apt() { [ "$PKG_MANAGER" = "apt" ]; }
is_dnf() { [ "$PKG_MANAGER" = "dnf" ]; }

ensure_command() {
    local cmd=$1
    local pkg_apt=${2:-$1}
    local pkg_dnf=${3:-$1}
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${C_YELLOW}Installing missing dependency: $cmd${C_RESET}"
        if is_apt; then
            sudo apt install -y "$pkg_apt"
        elif is_dnf; then
            sudo dnf install -y "$pkg_dnf"
        fi
    fi
}

clone_if_missing() {
    local repo=$1
    local dest=$2
    if [ ! -d "$dest" ]; then
        echo "Cloning $(basename "$dest")..."
        git clone "$repo" "$dest"
    else
        echo -e "${C_YELLOW}Already installed/exists: $(basename "$dest")${C_RESET}"
    fi
}

# Loads optional settings from the git-ignored .env (see .env.example for the keys).
load_env() {
    if [ -f "$DOTFILES_DIR/.env" ]; then
        # shellcheck source=/dev/null
        source "$DOTFILES_DIR/.env"
    fi
}

# Flathub as a system remote. Fedora may ship it disabled or filtered.
ensure_flathub() {
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    sudo flatpak remote-modify --enable --no-filter flathub
}
