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

find "$DOTFILES_DIR/style" "$DOTFILES_DIR/tools" -name "*.sh" -exec chmod +x {} +

echo -e "${C_GREEN}Permissions set.${C_RESET}"
