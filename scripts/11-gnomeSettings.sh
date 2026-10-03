#!/bin/bash
# MENU_DESC: GNOME extensions, settings and shortcuts
# CATEGORY: CUSTOMIZATION
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro

# Everything applied here is captured from a configured machine by
# style/gnome/bin/export-gnome-settings.sh.
GNOME_DIR="$DOTFILES_DIR/style/gnome"

if ! command -v gnome-shell &>/dev/null; then
    echo -e "${C_YELLOW}GNOME Shell not found. Nothing to configure.${C_RESET}"
    exit 0
fi

# dconf writes through the session bus, so this must run inside the graphical session
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    echo -e "${C_RED}No D-Bus session found. Run this module from a terminal inside the GNOME session.${C_RESET}" >&2
    exit 1
fi

ensure_command curl curl curl
ensure_command python3 python3 python3   # parses the extensions.gnome.org API response
ensure_command dconf dconf-cli dconf

SHELL_VERSION="$(gnome-shell --version | awk '{ split($3, v, "."); print v[1] }')"

# ─── Extensions ───────────────────────────────────────────────────────────────
print_header "Installing GNOME extensions (GNOME Shell $SHELL_VERSION)"

extension_installed() {
    [ -d "$HOME/.local/share/gnome-shell/extensions/$1" ] || [ -d "/usr/share/gnome-shell/extensions/$1" ]
}

# Downloads the build made for this GNOME Shell version from extensions.gnome.org.
# It runs inside 'if', where set -e is off, so every step checks its own result.
install_from_ego() {
    local uuid=$1 url zip
    url="$(curl -fsS "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${SHELL_VERSION}" \
        | python3 -c 'import json, sys; print(json.load(sys.stdin)["download_url"])')" || return 1
    # Only a plain path on extensions.gnome.org is accepted: nothing that could change the
    # host once appended to the base URL (e.g. "@other-host/..." or "//other-host/...")
    if ! [[ "$url" =~ ^/download-extension/[A-Za-z0-9@._-]+\.shell-extension\.zip(\?version_tag=[0-9]+)?$ ]]; then
        echo -e "${C_RED}Unexpected download URL for $uuid: $url${C_RESET}" >&2
        return 1
    fi
    zip="$(mktemp --suffix=.zip)" || return 1
    if ! curl -fsSL -o "$zip" "https://extensions.gnome.org${url}" || ! gnome-extensions install --force "$zip"; then
        rm -f "$zip"
        return 1
    fi
    rm -f "$zip"
}

dnf_packages=()
ego_extensions=()
# extensions.txt: "UUID [Fedora package]" per line; '#' starts a comment
while read -r uuid package _; do
    if [ -z "$uuid" ] || [[ "$uuid" == \#* ]]; then
        continue
    fi
    if extension_installed "$uuid"; then
        echo -e "${C_YELLOW}Already installed: $uuid${C_RESET}"
    elif [ -n "$package" ] && is_dnf; then
        dnf_packages+=("$package")
    else
        ego_extensions+=("$uuid")
    fi
done < "$GNOME_DIR/extensions.txt"

# Native package first (updated by dnf), extensions.gnome.org for the rest
if [ ${#dnf_packages[@]} -gt 0 ]; then
    sudo dnf install -y "${dnf_packages[@]}"
fi

failed=()
for uuid in "${ego_extensions[@]}"; do
    echo "Installing $uuid from extensions.gnome.org..."
    if ! install_from_ego "$uuid"; then
        echo -e "${C_RED}Could not install $uuid for GNOME Shell $SHELL_VERSION.${C_RESET}" >&2
        failed+=("$uuid")
    fi
done

# ─── Extension data files ─────────────────────────────────────────────────────
if compgen -G "$GNOME_DIR/burn-my-windows/profiles/*.conf" > /dev/null; then
    mkdir -p "$HOME/.config/burn-my-windows/profiles"
    cp "$GNOME_DIR"/burn-my-windows/profiles/*.conf "$HOME/.config/burn-my-windows/profiles/"
fi

# ─── Settings ─────────────────────────────────────────────────────────────────
# Desktop, input, power, extension preferences, enabled extensions, dock favorites
# and every shortcut. Loading only sets the listed keys; reruns are harmless.
print_header "Applying GNOME settings and shortcuts"

for ini in "$GNOME_DIR"/dconf/*.ini; do
    echo "Loading $(basename "$ini")..."
    sed "s|@HOME@|$HOME|g" "$ini" | dconf load /
done

if [ ${#failed[@]} -gt 0 ]; then
    echo -e "${C_RED}Settings applied, but these extensions were not installed: ${failed[*]}${C_RESET}" >&2
    echo -e "${C_YELLOW}They may not support GNOME Shell $SHELL_VERSION yet. Rerun this module later or use Extension Manager.${C_RESET}" >&2
    exit 1
fi

echo -e "${C_GREEN}GNOME configured. Log out and back in to load newly installed extensions.${C_RESET}"
