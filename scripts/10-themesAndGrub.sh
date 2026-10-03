#!/bin/bash
# MENU_DESC: Install GNOME Themes, Icons, GRUB & Plymouth
# CATEGORY: CUSTOMIZATION
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro
load_env

print_header "Installing Theme Dependencies"

# sassc compiles the Orchis CSS. inkscape/optipng are only used by the theme
# authors' asset render scripts, not by install.sh (Inkscape itself is a Flatpak).
# The plymouth packages provide plymouth-set-default-theme and the script plugin.
if is_apt; then
    sudo apt update
    sudo apt install -y sassc plymouth plymouth-themes
elif is_dnf; then
    sudo dnf install -y sassc plymouth plymouth-plugin-script
fi

ensure_command git git git

temp_dir=$(mktemp -d)
cleanup() { rm -rf "$temp_dir"; }
trap cleanup EXIT

# Returns 0 when $1 exists in any of the directories given after it
theme_installed() {
    local name=$1 dir
    shift
    for dir in "$@"; do
        [ -e "$dir/$name" ] && return 0
    done
    return 1
}

# $1: name, $2: repository URL, remaining arguments go to the repository's install.sh
install_from_repo() {
    local name=$1 repo=$2
    shift 2
    echo "Downloading $name..."
    git clone --depth=1 "$repo" "$temp_dir/$name"
    (cd "$temp_dir/$name" && ./install.sh "$@")
}

THEME_DIRS=("$HOME/.themes" "$HOME/.local/share/themes" "${XDG_DATA_HOME:-$HOME/.local/share}/themes")
ICON_DIRS=("$HOME/.local/share/icons" "$HOME/.icons")

# ─── GNOME Themes (Orchis, Tela Circle, Vimix) ────────────────────────────────
# Names must match style/gnome/dconf/desktop.ini (Orchis-Dark, Tela-circle-dark, Vimix-cursors),
# which module 11 applies.
print_header "Installing Orchis Theme, Tela Circle Icons & Vimix Cursors"

# Default color only (Orchis, Orchis-Dark, Orchis-Light and their compact/hdpi sizes)
if theme_installed Orchis "${THEME_DIRS[@]}"; then
    echo -e "${C_YELLOW}Orchis theme already installed. Skipping.${C_RESET}"
else
    install_from_repo Orchis-theme https://github.com/vinceliuice/Orchis-theme.git
fi

# Standard color only: provides Tela-circle, Tela-circle-dark and Tela-circle-light
if theme_installed Tela-circle "${ICON_DIRS[@]}"; then
    echo -e "${C_YELLOW}Tela Circle icons already installed. Skipping.${C_RESET}"
else
    install_from_repo Tela-circle-icon-theme https://github.com/vinceliuice/Tela-circle-icon-theme.git
fi

if theme_installed Vimix-cursors "${ICON_DIRS[@]}"; then
    echo -e "${C_YELLOW}Vimix cursors already installed. Skipping.${C_RESET}"
else
    install_from_repo Vimix-cursors https://github.com/vinceliuice/Vimix-cursors.git
fi

# ─── GRUB Configuration ───────────────────────────────────────────────────────
print_header "Configuring GRUB (Hidden + Theme)"

GRUB_CONF="/etc/default/grub"

# Replaces KEY=... in /etc/default/grub, or appends it when missing (Fedora has no GRUB_TIMEOUT_STYLE line)
set_grub_option() {
    if grep -q "^$1=" "$GRUB_CONF"; then
        sudo sed -i "s/^$1=.*/$1=$2/" "$GRUB_CONF"
    else
        echo "$1=$2" | sudo tee -a "$GRUB_CONF" > /dev/null
    fi
}

if [ -f "$GRUB_CONF" ]; then
    # Backup only once, so reruns keep the original file
    if [ ! -f "${GRUB_CONF}.bak" ]; then
        sudo cp -a "$GRUB_CONF" "${GRUB_CONF}.bak"
    fi

    # Hide GRUB but keep it ready
    set_grub_option GRUB_TIMEOUT 0
    set_grub_option GRUB_TIMEOUT_STYLE hidden

    # Custom GRUB theme (cloned by 01-setupEnv.sh). Without arguments its installer
    # opens an interactive dialog, so the options come from GRUB_THEME_ARGS in .env.
    GRUB_THEME_DIR="$HOME/Dev/linux_projects/gnome/grub2/grub2-theme"
    if [ -z "${GRUB_THEME_ARGS:-}" ]; then
        echo -e "${C_YELLOW}GRUB_THEME_ARGS not set in .env. Skipping custom GRUB theme.${C_RESET}"
    elif [ ! -x "$GRUB_THEME_DIR/install.sh" ]; then
        echo -e "${C_YELLOW}GRUB theme repository not found at $GRUB_THEME_DIR (run 01-setupEnv.sh). Skipping.${C_RESET}"
    else
        echo "Installing custom GRUB theme..."
        read -r -a grub_theme_args <<< "$GRUB_THEME_ARGS"
        (cd "$GRUB_THEME_DIR" && sudo ./install.sh "${grub_theme_args[@]}")
    fi

    echo "Updating GRUB..."
    if is_apt; then
        sudo update-grub
    elif is_dnf; then
        # Fedora 34+: /boot/efi/EFI/fedora/grub.cfg is a stub that chains to this file.
        # Never write the full config over that stub.
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
else
    echo -e "${C_YELLOW}$GRUB_CONF not found (systemd-boot?). Skipping GRUB.${C_RESET}"
fi

# ─── Plymouth Configuration ───────────────────────────────────────────────────
# Boot splash "deus_ex" from adi1090x/plymouth-themes (pack_2). It is a script theme,
# hence the plymouth script plugin installed above.
PLYMOUTH_THEME="deus_ex"
PLYMOUTH_PACK="pack_2"
print_header "Configuring Plymouth ($PLYMOUTH_THEME)"

# Fedora and Debian ship plymouth-set-default-theme; Ubuntu manages the theme as an alternative
current_plymouth_theme() {
    if command -v plymouth-set-default-theme &>/dev/null; then
        plymouth-set-default-theme
    else
        basename "$(dirname "$(readlink -f /usr/share/plymouth/themes/default.plymouth)")"
    fi
}

set_plymouth_theme() {
    if command -v plymouth-set-default-theme &>/dev/null; then
        # -R rebuilds the initramfs (dracut on Fedora), which is where the splash is loaded from
        sudo plymouth-set-default-theme -R "$1"
    else
        local file="/usr/share/plymouth/themes/$1/$1.plymouth"
        sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$file" 100
        sudo update-alternatives --set default.plymouth "$file"
        sudo update-initramfs -u
    fi
}

if [ "$(current_plymouth_theme)" = "$PLYMOUTH_THEME" ]; then
    echo -e "${C_YELLOW}Plymouth theme $PLYMOUTH_THEME already active. Skipping.${C_RESET}"
else
    if [ ! -d "/usr/share/plymouth/themes/$PLYMOUTH_THEME" ]; then
        # Sparse clone: only this theme's folder is downloaded (a few MB, not the whole collection)
        git clone --depth=1 --filter=blob:none --sparse \
            https://github.com/adi1090x/plymouth-themes.git "$temp_dir/plymouth-themes"
        git -C "$temp_dir/plymouth-themes" sparse-checkout set "$PLYMOUTH_PACK/$PLYMOUTH_THEME"
        sudo cp -r "$temp_dir/plymouth-themes/$PLYMOUTH_PACK/$PLYMOUTH_THEME" /usr/share/plymouth/themes/
    fi
    set_plymouth_theme "$PLYMOUTH_THEME"
fi

echo -e "${C_GREEN}Themes, Icons, GRUB and Plymouth configured.${C_RESET}"
