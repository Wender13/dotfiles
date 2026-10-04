#!/bin/bash
# MENU_DESC: Install GNOME Themes, Icons, GRUB & Plymouth
# CATEGORY: CUSTOMIZATION
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro
load_env

print_header "Installing Theme Dependencies"

# sassc compiles the Orchis CSS (GNOME only). inkscape/optipng are only used by the theme
# authors' asset render scripts, not by install.sh (Inkscape itself is a Flatpak).
# The plymouth packages provide plymouth-set-default-theme and the script plugin.
THEME_DEPS=()
if is_gnome; then
    THEME_DEPS+=(sassc)
fi
if is_apt; then
    sudo apt update
    install_packages "10 - dependencias de temas" "${THEME_DEPS[@]}" plymouth plymouth-themes
elif is_dnf; then
    install_packages "10 - dependencias de temas" "${THEME_DEPS[@]}" plymouth plymouth-plugin-script
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

# $1: name, $2: repository URL, remaining arguments go to the repository's install.sh.
# The installed commit is recorded, so later runs can tell whether upstream has news.
install_from_repo() {
    local name=$1 repo=$2
    shift 2
    echo "Downloading $name..."
    rm -rf "${temp_dir:?}/$name"
    git clone --depth=1 "$repo" "$temp_dir/$name"
    (cd "$temp_dir/$name" && ./install.sh "$@")
    record_version "$name" "$(git -C "$temp_dir/$name" rev-parse --short=12 HEAD)"
}

# Latest commit of a repository (12 characters, as recorded), or nothing if unreachable.
# The empty result is handled by the callers ("could not check"), hence the || true.
remote_head() {
    git ls-remote "$1" HEAD 2> /dev/null | cut -c1-12 || true
}

THEME_DIRS=("$HOME/.themes" "$HOME/.local/share/themes" "${XDG_DATA_HOME:-$HOME/.local/share}/themes")
ICON_DIRS=("$HOME/.local/share/icons" "$HOME/.icons")

# ─── GNOME Themes (Orchis, Tela Circle, Vimix) ────────────────────────────────
# Names must match style/gnome/dconf/desktop.ini (Orchis-Dark, Tela-circle-dark, Vimix-cursors),
# which module 11 applies.
print_header "Installing Orchis Theme, Tela Circle Icons & Vimix Cursors"

# name|repository|installed folder|where to look (theme or icon). Default install options:
# Orchis in the default color (Orchis, -Dark, -Light and their sizes), Tela Circle in the
# standard color (Tela-circle, -dark, -light), Vimix cursors.
THEMES=(
    "Orchis-theme|https://github.com/vinceliuice/Orchis-theme.git|Orchis|theme"
    "Tela-circle-icon-theme|https://github.com/vinceliuice/Tela-circle-icon-theme.git|Tela-circle|icon"
    "Vimix-cursors|https://github.com/vinceliuice/Vimix-cursors.git|Vimix-cursors|icon"
)
if ! gnome_only "the GNOME themes"; then
    THEMES=()
fi
theme_lines=()
theme_updates=()
for entry in "${THEMES[@]}"; do
    IFS='|' read -r name repo folder kind <<< "$entry"
    if [ "$kind" = "theme" ]; then dirs=("${THEME_DIRS[@]}"); else dirs=("${ICON_DIRS[@]}"); fi
    if ! theme_installed "$folder" "${dirs[@]}"; then
        install_from_repo "$name" "$repo"
        continue
    fi
    latest="$(remote_head "$repo")"
    current="$(recorded_version "$name")"
    if [ -z "$latest" ]; then
        echo -e "${C_YELLOW}$name is installed; could not check for a newer version.${C_RESET}"
    elif [ "$current" != "$latest" ]; then
        theme_lines+=("$name $current -> $latest")
        theme_updates+=("$entry")
    else
        echo -e "${C_YELLOW}$name is installed and up to date.${C_RESET}"
    fi
done
if confirm_updates "Temas (GTK, icones e cursores)" "${theme_lines[@]}"; then
    for entry in "${theme_updates[@]}"; do
        IFS='|' read -r name repo _ _ <<< "$entry"
        install_from_repo "$name" "$repo"
    done
fi

# ─── GRUB Configuration ───────────────────────────────────────────────────────
print_header "Configuring GRUB (Hidden + Theme)"

GRUB_CONF="/etc/default/grub"

# Backup only once, before the first change, so reruns keep the original file
backup_grub_conf() {
    if [ ! -f "${GRUB_CONF}.bak" ]; then
        sudo cp -a "$GRUB_CONF" "${GRUB_CONF}.bak"
    fi
}

# Replaces KEY=... in /etc/default/grub, or appends it when missing (Fedora has no GRUB_TIMEOUT_STYLE line)
set_grub_option() {
    if grep -q "^$1=" "$GRUB_CONF"; then
        sudo sed -i "s/^$1=.*/$1=$2/" "$GRUB_CONF"
    else
        echo "$1=$2" | sudo tee -a "$GRUB_CONF" > /dev/null
    fi
}

if [ -f "$GRUB_CONF" ]; then
    grub_changed=0
    if only_missing; then
        keep_existing "the GRUB menu settings (timeout and style)"
    else
        backup_grub_conf
        # Hide GRUB but keep it ready
        set_grub_option GRUB_TIMEOUT 0
        set_grub_option GRUB_TIMEOUT_STYLE hidden
        grub_changed=1
    fi

    # Custom GRUB theme (cloned by 01-setupEnv.sh). Without arguments its installer
    # opens an interactive dialog, so the options come from GRUB_THEME_ARGS in .env.
    GRUB_THEME_DIR="$HOME/Dev/linux_projects/gnome/grub2/grub2-theme"
    if [ -z "${GRUB_THEME_ARGS:-}" ]; then
        echo -e "${C_YELLOW}GRUB_THEME_ARGS not set in .env. Skipping custom GRUB theme.${C_RESET}"
    elif [ ! -x "$GRUB_THEME_DIR/install.sh" ]; then
        echo -e "${C_YELLOW}GRUB theme repository not found at $GRUB_THEME_DIR (run 01-setupEnv.sh). Skipping.${C_RESET}"
    elif only_missing && [ "$(recorded_version grub-theme)" = "desconhecida" ] && grep -q '^GRUB_THEME=' "$GRUB_CONF"; then
        # A theme this project did not install
        keep_existing "the GRUB theme already configured ($(sed -n 's/^GRUB_THEME=//p' "$GRUB_CONF"))"
    else
        # Installed state = fork commit + options; a new commit (pulled by module 01) or new
        # options count as a newer version
        grub_state="$(git -C "$GRUB_THEME_DIR" rev-parse --short=12 HEAD) $GRUB_THEME_ARGS"
        grub_recorded="$(recorded_version grub-theme)"
        install_grub_theme=0
        if [ "$grub_recorded" = "desconhecida" ]; then
            install_grub_theme=1
        elif [ "$grub_recorded" != "$grub_state" ]; then
            if confirm_updates "Tema do GRUB" "grub2-theme $grub_recorded -> $grub_state"; then
                install_grub_theme=1
            fi
        else
            echo -e "${C_YELLOW}Custom GRUB theme is installed and up to date.${C_RESET}"
        fi
        if [ "$install_grub_theme" -eq 1 ]; then
            echo "Installing custom GRUB theme..."
            read -r -a grub_theme_args <<< "$GRUB_THEME_ARGS"
            backup_grub_conf
            (cd "$GRUB_THEME_DIR" && sudo ./install.sh "${grub_theme_args[@]}")
            record_version grub-theme "$grub_state"
            grub_changed=1
        fi
    fi

    if [ "$grub_changed" -eq 1 ]; then
        echo "Updating GRUB..."
        if is_apt; then
            sudo update-grub
        elif is_dnf; then
            # Fedora 34+: /boot/efi/EFI/fedora/grub.cfg is a stub that chains to this file.
            # Never write the full config over that stub.
            sudo grub2-mkconfig -o /boot/grub2/grub.cfg
        fi
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

PLYMOUTH_REPO="https://github.com/adi1090x/plymouth-themes.git"

# Sparse clone: only this theme's folder is downloaded (a few MB, not the whole collection)
install_plymouth_files() {
    rm -rf "${temp_dir:?}/plymouth-themes"
    git clone --depth=1 --filter=blob:none --sparse "$PLYMOUTH_REPO" "$temp_dir/plymouth-themes"
    git -C "$temp_dir/plymouth-themes" sparse-checkout set "$PLYMOUTH_PACK/$PLYMOUTH_THEME"
    sudo mkdir -p "/usr/share/plymouth/themes/$PLYMOUTH_THEME"
    sudo cp -r "$temp_dir/plymouth-themes/$PLYMOUTH_PACK/$PLYMOUTH_THEME/." "/usr/share/plymouth/themes/$PLYMOUTH_THEME/"
    record_version "plymouth-$PLYMOUTH_THEME" "$(git -C "$temp_dir/plymouth-themes" rev-parse --short=12 HEAD)"
}

if only_missing && [ "$(current_plymouth_theme)" != "$PLYMOUTH_THEME" ]; then
    keep_existing "the current boot splash ($(current_plymouth_theme))"
elif [ "$(current_plymouth_theme)" != "$PLYMOUTH_THEME" ]; then
    if [ ! -d "/usr/share/plymouth/themes/$PLYMOUTH_THEME" ]; then
        install_plymouth_files
    fi
    set_plymouth_theme "$PLYMOUTH_THEME"
else
    latest="$(remote_head "$PLYMOUTH_REPO")"
    current="$(recorded_version "plymouth-$PLYMOUTH_THEME")"
    if [ -n "$latest" ] && [ "$current" != "$latest" ] \
        && confirm_updates "Tela de boot (Plymouth)" "$PLYMOUTH_THEME $current -> $latest"; then
        install_plymouth_files
        set_plymouth_theme "$PLYMOUTH_THEME"
    else
        echo -e "${C_YELLOW}Plymouth theme $PLYMOUTH_THEME is active.${C_RESET}"
    fi
fi

echo -e "${C_GREEN}Themes, Icons, GRUB and Plymouth configured.${C_RESET}"
