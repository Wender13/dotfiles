#!/bin/bash
# MENU_DESC: Install Flatpak packages
# CATEGORY: PROGRAMS
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro

print_header "Installing Flatpak programs"

ensure_command flatpak
ensure_flathub

FLATPAK_APPS=(
    md.obsidian.Obsidian
    com.getpostman.Postman
    rest.insomnia.Insomnia
    org.onlyoffice.desktopeditors
    com.discordapp.Discord
    io.dbeaver.DBeaverCommunity
    com.mongodb.Compass
    org.localsend.localsend_app
    com.mattjakeman.ExtensionManager
    org.prismlauncher.PrismLauncher
    org.zotero.Zotero
    io.podman_desktop.PodmanDesktop
    org.inkscape.Inkscape
)

# System-wide, same scope as the Flathub remote. --or-update keeps reruns from failing.
echo -e "${C_BLUE}Instalando aplicativos via Flatpak...${C_RESET}"
sudo flatpak install -y --or-update flathub "${FLATPAK_APPS[@]}"

echo -e "${C_GREEN}Flatpak programs installed.${C_RESET}"
