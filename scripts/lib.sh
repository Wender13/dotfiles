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
        # Debian itself: 13 (trixie) or newer. Testing and sid have no VERSION_ID.
        if [ "${ID:-}" = "debian" ] && [ -n "${VERSION_ID:-}" ] && [ "${VERSION_ID%%.*}" -lt 13 ]; then
            echo -e "${C_RED}Debian 13 (trixie) or newer is required (found Debian ${VERSION_ID}).${C_RESET}" >&2
            exit 1
        fi
        PKG_MANAGER="apt"
    else
        echo -e "${C_RED}Unsupported distribution: ${ID:-unknown}${C_RESET}" >&2
        exit 1
    fi
}

is_apt() { [ "$PKG_MANAGER" = "apt" ]; }
is_dnf() { [ "$PKG_MANAGER" = "dnf" ]; }
# Debian itself, not Ubuntu or another derivative (after detect_distro)
is_debian() { [ "${ID:-}" = "debian" ]; }

# Group whose members may use sudo: wheel on Fedora, sudo on Debian and Ubuntu
admin_group() {
    if is_dnf; then echo "wheel"; else echo "sudo"; fi
}

# True when this session can already use sudo: the command exists and the session belongs
# to an admin group (a group added later only counts after a new login) or has a cached
# sudo credential. Module 00 sets this up when it is missing.
has_sudo_access() {
    command -v sudo > /dev/null || return 1
    if id -nG | tr ' ' '\n' | grep -qxE 'sudo|wheel|admin'; then
        return 0
    fi
    sudo -n true 2> /dev/null
}

# ─── Desktop ──────────────────────────────────────────────────────────────────
# The project targets GNOME. Everything GNOME-specific (settings, extensions, themes, GNOME
# apps) runs only when GNOME is detected; on other desktops it is skipped, never an error.
# GNOME: GNOME Shell is installed and the graphical session is GNOME (XDG_CURRENT_DESKTOP is
# "GNOME" on Fedora, "ubuntu:GNOME" on Ubuntu). Without a graphical session (TTY, SSH),
# having GNOME Shell installed is enough.
is_gnome() {
    command -v gnome-shell &> /dev/null || return 1
    [ -z "${XDG_CURRENT_DESKTOP:-}" ] || [[ ":${XDG_CURRENT_DESKTOP^^}:" == *:GNOME:* ]]
}

# Guard for a GNOME step inside a module: returns 1, saying what is skipped, elsewhere.
# Usage: if gnome_only "GNOME Tweaks"; then ...; fi
gnome_only() {
    if is_gnome; then
        return 0
    fi
    echo -e "${C_YELLOW}GNOME not detected (desktop: ${XDG_CURRENT_DESKTOP:-unknown}). Skipping $1.${C_RESET}"
    return 1
}

# For modules that only configure GNOME: elsewhere, ends the module successfully
require_gnome() {
    if ! is_gnome; then
        echo -e "${C_YELLOW}GNOME not detected (desktop: ${XDG_CURRENT_DESKTOP:-unknown}). This module only configures GNOME: skipping.${C_RESET}"
        exit 0
    fi
}

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

# ─── Config mode ──────────────────────────────────────────────────────────────
# What happens to what the system already has:
#   full    - apply the repository configuration (the original behavior)
#   missing - complete a system that is already partly set up: install what is missing,
#             remove nothing, and set only what is still unset (files that do not exist,
#             git and dconf keys still at their default). Settings that always have a
#             value (default shell, GRUB, boot splash, wallpaper, services) are kept,
#             unless their software was installed by the same run.
# app.sh passes it in DOTFILES_CONFIG_MODE (--full/--only-missing or CONFIG_MODE in .env).
resolve_config_mode() {
    local mode="${DOTFILES_CONFIG_MODE:-}"
    if [ -z "$mode" ] && [ -f "$DOTFILES_DIR/.env" ]; then
        mode="$(bash -c 'source "$1" > /dev/null 2>&1; printf "%s" "${CONFIG_MODE:-}"' _ "$DOTFILES_DIR/.env")"
    fi
    case "${mode:-full}" in
        full|missing) CONFIG_MODE="${mode:-full}" ;;
        *)
            echo -e "${C_RED}Invalid config mode '$mode' (use full or missing).${C_RESET}" >&2
            exit 1
            ;;
    esac
}
resolve_config_mode

only_missing() { [ "$CONFIG_MODE" = "missing" ]; }

# Says that an existing setting was left as it is (only-missing mode)
keep_existing() {
    echo -e "${C_YELLOW}Only-missing mode: keeping $1.${C_RESET}"
}

# ─── Update policy ────────────────────────────────────────────────────────────
# What happens when something is already installed and a newer version exists:
#   ask    - list "current -> new", warn and ask once per group (default answer: keep)
#   update - update without asking (the warning is still shown)
#   keep   - never touch what is installed; only what is missing gets installed
# app.sh passes it in DOTFILES_UPDATE_POLICY (--ask/--update/--keep or UPDATE_POLICY
# in .env). A module run on its own reads .env, and asks only when on a terminal.
# The only-missing mode defaults to keep: updating is not completing.
UPDATE_WARNING="Atencao: versoes novas podem mudar comportamento ou quebrar recursos (configuracoes, plugins, compatibilidade de projetos)."
VERSIONS_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/versions"

resolve_update_policy() {
    local policy="${DOTFILES_UPDATE_POLICY:-}"
    if [ -z "$policy" ] && [ -f "$DOTFILES_DIR/.env" ]; then
        policy="$(bash -c 'source "$1" > /dev/null 2>&1; printf "%s" "${UPDATE_POLICY:-}"' _ "$DOTFILES_DIR/.env")"
    fi
    if [ -z "$policy" ]; then
        if only_missing || [ ! -t 0 ]; then policy="keep"; else policy="ask"; fi
    fi
    case "$policy" in
        ask|update|keep) ;;
        *)
            echo -e "${C_RED}Invalid update policy '$policy' (use ask, update or keep).${C_RESET}" >&2
            exit 1
            ;;
    esac
    if [ "$policy" = "ask" ] && [ ! -t 0 ]; then
        echo -e "${C_YELLOW}No terminal to ask on: keeping installed versions (policy keep).${C_RESET}"
        policy="keep"
    fi
    UPDATE_POLICY="$policy"
}
resolve_update_policy

# $1: group title; remaining arguments: "name current -> new" lines.
# Returns 0 to update the group, 1 to keep the installed versions.
confirm_updates() {
    local title=$1 answer=""
    shift
    if [ $# -eq 0 ]; then
        return 1
    fi
    echo -e "\n${C_CYAN}${C_BOLD}${title}: $# item(s) com versao mais nova${C_RESET}"
    printf '    %s\n' "$@"
    if [ "$UPDATE_POLICY" = "keep" ]; then
        echo -e "${C_YELLOW}  Politica keep: mantendo as versoes instaladas.${C_RESET}"
        return 1
    fi
    echo -e "${C_YELLOW}  ${UPDATE_WARNING}${C_RESET}"
    if [ "$UPDATE_POLICY" = "update" ]; then
        echo "  Politica update: atualizando."
        return 0
    fi
    read -r -p "  Atualizar? [s/N] " answer || true
    [[ "$answer" =~ ^[sSyY]$ ]]
}

# Name of the installed package that provides $1 (handles virtual names such as wget)
installed_package() {
    local out
    if is_dnf; then
        out="$(rpm -q --whatprovides --qf '%{NAME}\n' "$1" 2> /dev/null)" || return 1
    else
        out="$(dpkg-query -W -f='${db:Status-Status} ${Package}\n' "$1" 2> /dev/null)" || return 1
        [[ "$out" == installed\ * ]] || return 1
        out="${out#installed }"
    fi
    printf '%s\n' "${out%%$'\n'*}"
}

# "name current -> new" for every installed package among the arguments with a newer version
package_upgrades() {
    local pkg name names=() current
    for pkg in "$@"; do
        [[ "$pkg" == @* ]] && continue
        if name="$(installed_package "$pkg")"; then
            names+=("$name")
        fi
    done
    if [ ${#names[@]} -eq 0 ]; then
        return 0
    fi
    if is_dnf; then
        dnf repoquery --upgrades --latest-limit=1 --qf '%{name} %{evr}\n' "${names[@]}" 2> /dev/null | sort -u \
            | while read -r name new; do
                current="$(rpm -q --qf '%{EVR}\n' "$name" | head -n1)"
                echo "$name $current -> $new"
            done
    else
        # Lines look like: name/suite 2.0-1 amd64 [upgradable from: 1.0-1]
        apt list --upgradable 2> /dev/null | awk -v list="${names[*]}" '
            BEGIN { n = split(list, a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1 }
            { split($1, p, "/") }
            p[1] in want { old = $NF; sub(/\]$/, "", old); print p[1], old, "->", $2 }'
    fi
}

# Installs the packages that are missing; installed ones are never upgraded here
install_missing_packages() {
    local pkg missing=()
    for pkg in "$@"; do
        if [[ "$pkg" == @* ]] || ! installed_package "$pkg" > /dev/null; then
            missing+=("$pkg")
        fi
    done
    if [ ${#missing[@]} -eq 0 ]; then
        echo -e "${C_YELLOW}All requested packages are already installed.${C_RESET}"
        return 0
    fi
    if is_dnf; then
        sudo dnf install -y "${missing[@]}"
    else
        sudo apt-get install -y "${missing[@]}"
    fi
}

# Offers newer versions of the installed packages among the arguments ($1 is the group title)
offer_package_upgrades() {
    local title=$1 lines=() names=() line
    shift
    mapfile -t lines < <(package_upgrades "$@")
    if confirm_updates "$title" "${lines[@]}"; then
        for line in "${lines[@]}"; do
            names+=("${line%% *}")
        done
        if is_dnf; then
            sudo dnf upgrade -y "${names[@]}"
        else
            sudo apt-get install -y --only-upgrade "${names[@]}"
        fi
    fi
}

# Missing packages are installed; installed ones with a newer version follow the policy
install_packages() {
    local title=$1
    shift
    install_missing_packages "$@"
    offer_package_upgrades "$title" "$@"
}

# Flatpak apps (system scope): installs the missing ones; updates follow the policy
install_flatpaks() {
    local app missing=() installed=() lines=() names=() updates current new line
    for app in "$@"; do
        if flatpak info --system "$app" &> /dev/null; then
            installed+=("$app")
        else
            missing+=("$app")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        sudo flatpak install -y flathub "${missing[@]}"
    fi
    if [ ${#installed[@]} -eq 0 ]; then
        return 0
    fi
    # Offline: no update information, so installed apps are just kept
    updates="$(flatpak remote-ls --system --updates --app --columns=application,version 2> /dev/null)" || updates=""
    for app in "${installed[@]}"; do
        line="$(awk -F'\t' -v a="$app" '$1 == a' <<< "$updates")"
        if [ -z "$line" ]; then
            continue
        fi
        new="$(cut -f2 <<< "$line")"
        current="$(flatpak list --system --app --columns=application,version | awk -F'\t' -v a="$app" '$1 == a { print $2 }')"
        if [ "$new" = "$current" ]; then
            new="$new (nova revisao)"
        fi
        lines+=("$app ${current:-?} -> ${new:-?}")
    done
    if confirm_updates "Flatpak" "${lines[@]}"; then
        for line in "${lines[@]}"; do
            names+=("${line%% *}")
        done
        sudo flatpak update -y "${names[@]}"
    fi
}

# Git clones (plugins, themes, personal forks): offers a fast-forward when the upstream
# has new commits. Clones with local changes or a diverged history are reported and left
# alone, so local work is never overwritten.
offer_git_updates() {
    local title=$1 dir name behind lines=() dirs=()
    shift
    for dir in "$@"; do
        [ -d "$dir/.git" ] || continue
        name="$(basename "$dir")"
        if ! git -C "$dir" fetch --quiet 2> /dev/null; then
            echo -e "${C_YELLOW}Could not check $name for updates (fetch failed).${C_RESET}"
            continue
        fi
        behind="$(git -C "$dir" rev-list --count 'HEAD..@{upstream}' 2> /dev/null)" || continue
        if [ "$behind" -eq 0 ]; then
            continue
        elif [ -n "$(git -C "$dir" status --porcelain)" ]; then
            echo -e "${C_YELLOW}$name: $behind new upstream commit(s), but it has local changes. Not updated.${C_RESET}"
        elif ! git -C "$dir" merge-base --is-ancestor HEAD '@{upstream}'; then
            echo -e "${C_YELLOW}$name: history diverged from upstream (local commits). Not updated.${C_RESET}"
        else
            lines+=("$name $(git -C "$dir" rev-parse --short HEAD) -> $(git -C "$dir" rev-parse --short '@{upstream}') ($behind commit(s))")
            dirs+=("$dir")
        fi
    done
    if confirm_updates "$title" "${lines[@]}"; then
        for dir in "${dirs[@]}"; do
            git -C "$dir" merge --ff-only --quiet '@{upstream}'
        done
    fi
}

# True when version $1 is newer than $2 (leading "v" ignored)
version_gt() {
    local a="${1#v}" b="${2#v}"
    [ "$a" != "$b" ] && [ "$(printf '%s\n' "$a" "$b" | sort -V | tail -n1)" = "$a" ]
}

# Versions of things installed without a package manager (themes, fonts)
record_version() {
    mkdir -p "$VERSIONS_DIR"
    printf '%s\n' "$2" > "$VERSIONS_DIR/$1"
}

recorded_version() {
    if [ -f "$VERSIONS_DIR/$1" ]; then
        cat "$VERSIONS_DIR/$1"
    else
        echo "desconhecida"
    fi
}
