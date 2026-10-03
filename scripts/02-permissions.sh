#!/bin/bash
# MENU_DESC: Set file and directory permissions
# CATEGORY:
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro

print_header "Setting script permissions"

chmod +x "$DOTFILES_DIR/app.sh"
find "$SCRIPT_DIR" -name "*.sh" -exec chmod +x {} +

GNOME_SCRIPTS="$DOTFILES_DIR/style/gnome"
if [ -d "$GNOME_SCRIPTS" ]; then
    find "$GNOME_SCRIPTS" -name "*.sh" -exec chmod +x {} +
    if [ -f "$GNOME_SCRIPTS/bin/changeWallpaper" ]; then
        chmod +x "$GNOME_SCRIPTS/bin/changeWallpaper"
    fi
fi

echo -e "${C_GREEN}Permissions set.${C_RESET}"
