#!/bin/bash
# MENU_DESC: Set up Dev folders and personal repos
# CATEGORY: ENVIRONMENT
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro
load_env

print_header "Setting up Dev folder structure"

# ─── Directory structure ──────────────────────────────────────────────────────
mkdir -p "$HOME/Dev/linux_projects/gnome/extensions"
mkdir -p "$HOME/Dev/linux_projects/gnome/grub2"
mkdir -p "$HOME/Dev/linux_projects/gnome/plymouth"
mkdir -p "$HOME/Dev/personal_projects"
mkdir -p "$HOME/Dev/college_projects"

echo -e "${C_GREEN}Folders created.${C_RESET}"

# ─── Personal forks (GNOME extensions and GRUB theme) ────────────────────────
print_header "Cloning personal repositories"

# The GitHub user comes from .env (GITHUB_USER) or a prompt, never from the code.
github_user="${GITHUB_USER:-}"
if [ -z "$github_user" ] && [ -t 0 ]; then
    read -r -p "Type your GitHub username (empty to skip): " github_user || true
fi

# GitHub usernames: letters, digits and single hyphens, up to 39 characters. Anything else
# is a typo or garbage and must not become part of a clone URL (the GRUB theme from these
# repositories is later installed with sudo by 10-themesAndGrub.sh).
if [ -n "$github_user" ] && { [ ${#github_user} -gt 39 ] || ! [[ "$github_user" =~ ^[A-Za-z0-9]([A-Za-z0-9]|-[A-Za-z0-9])*$ ]]; }; then
    echo -e "${C_RED}Invalid GitHub username: '$github_user'. Fix GITHUB_USER in .env.${C_RESET}" >&2
    exit 1
fi

if [ -z "$github_user" ]; then
    echo -e "${C_YELLOW}GITHUB_USER not set. Skipping personal repositories.${C_RESET}"
else
    ensure_command git

    forks=("$HOME/Dev/linux_projects/gnome/grub2/grub2-theme")
    clone_if_missing "https://github.com/$github_user/grub2-theme.git" "${forks[0]}"

    if gnome_only "the GNOME extension forks (hidetopbar, lockkeys)"; then
        ext_dir="$HOME/Dev/linux_projects/gnome/extensions"
        clone_if_missing "https://github.com/$github_user/hidetopbar.git" "$ext_dir/hidetopbar"
        clone_if_missing "https://github.com/$github_user/gnome-shell-extension-lockkeys.git" \
            "$ext_dir/gnome-shell-extension-lockkeys"
        forks+=("$ext_dir/hidetopbar" "$ext_dir/gnome-shell-extension-lockkeys")
    fi

    # These are working copies: only clean ones are fast-forwarded (see offer_git_updates)
    offer_git_updates "Forks pessoais (GitHub)" "${forks[@]}"
fi

echo -e "${C_GREEN}Environment setup complete.${C_RESET}"
