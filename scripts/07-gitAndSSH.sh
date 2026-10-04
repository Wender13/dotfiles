#!/bin/bash
# MENU_DESC: Configure Git and SSH keys
# CATEGORY: DEVELOPMENT
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro
load_env

ensure_command git

print_header "Setting Git"

# Only-missing mode: an identity already in ~/.gitconfig is kept and not asked again.
# (An empty result just means "not set"; git exits 1 for a missing key.)
current_name="$(git config --global --get user.name)" || current_name=""
current_email="$(git config --global --get user.email)" || current_email=""

git_username=${GIT_USERNAME:-}
if only_missing && [ -n "$current_name" ]; then
    git_username="$current_name"
elif [ -z "$git_username" ]; then
    read -r -p "Type your git username: " git_username || true
fi

git_email=${GIT_EMAIL:-}
if only_missing && [ -n "$current_email" ]; then
    git_email="$current_email"
elif [ -z "$git_email" ]; then
    read -r -p "Type your git e-mail: " git_email || true
fi

if [ -z "$git_username" ] || [ -z "$git_email" ]; then
    echo -e "${C_RED}Git username and e-mail are required (set GIT_USERNAME and GIT_EMAIL in .env).${C_RESET}" >&2
    exit 1
fi

# $1: key, $2: value. Only-missing mode: a key you already set is kept.
set_git_option() {
    local current
    current="$(git config --global --get "$1")" || current=""
    if only_missing && [ -n "$current" ]; then
        keep_existing "git $1 ($current)"
    else
        git config --global "$1" "$2"
    fi
}

set_git_option user.name "$git_username"
set_git_option user.email "$git_email"
set_git_option init.defaultBranch main
set_git_option color.ui auto

echo "Configured Git user:"
git config --get user.name
git config --get user.email

print_header "Setting SSH key"

if compgen -G "$HOME/.ssh/*.pub" > /dev/null; then
    echo -e "${C_YELLOW}SSH key already exists. Skipping generation.${C_RESET}"
elif [ -f "$HOME/.ssh/id_ed25519" ]; then
    # Private key without its public half: rebuild the .pub instead of asking to overwrite the key
    echo "Recreating the missing public key from $HOME/.ssh/id_ed25519..."
    ssh-keygen -y -f "$HOME/.ssh/id_ed25519" > "$HOME/.ssh/id_ed25519.pub"
else
    echo "Generating SSH key..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$git_email" -f "$HOME/.ssh/id_ed25519" -N ""
fi

echo "Your SSH public key is:"
cat "$HOME"/.ssh/*.pub

echo -e "${C_GREEN}Git configured.${C_RESET}"
