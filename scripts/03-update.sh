#!/bin/bash
# MENU_DESC: Update system and packages
# CATEGORY: SYSTEM
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro

print_header "Updating system and packages"

# One command per line: a failure inside an '&&' chain would not stop the script.
if is_apt; then
    sudo apt update
    sudo apt upgrade -y
    sudo apt dist-upgrade -y
    sudo apt autoremove -y
elif is_dnf; then
    sudo dnf upgrade --refresh -y
    sudo dnf autoremove -y
fi

if command -v flatpak &>/dev/null; then
    print_header "Updating Flatpak applications"
    sudo flatpak update -y
fi

echo -e "${C_GREEN}System and packages updated.${C_RESET}"
