#!/bin/bash
# MENU_DESC: Choose wallpaper and user picture
# CATEGORY: CUSTOMIZATION
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro
load_env

# The images come from .env (WALLPAPER_IMAGE, AVATAR_IMAGE) or are chosen when the module
# runs. They never go into the repository: it is public and pictures are personal.

require_gnome

# gsettings writes through the session bus, so this must run inside the graphical session
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    echo -e "${C_RED}No D-Bus session found. Run this module from a terminal inside the GNOME session.${C_RESET}" >&2
    exit 1
fi

ensure_command python3 python3 python3
ensure_command dconf dconf-cli dconf   # tells a wallpaper you set from the default one
# GdkPixbuf is what GNOME uses to draw wallpapers and user pictures, so an image it opens
# here is an image GNOME can show
if ! python3 -c 'import gi; gi.require_version("GdkPixbuf", "2.0"); from gi.repository import GdkPixbuf' 2> /dev/null; then
    if is_dnf; then
        install_missing_packages python3-gobject gdk-pixbuf2
    else
        install_missing_packages python3-gi gir1.2-gdkpixbuf-2.0
    fi
fi

PICTURES_DIR="$(xdg-user-dir PICTURES 2> /dev/null)" || PICTURES_DIR="$HOME"
[ -d "$PICTURES_DIR" ] || PICTURES_DIR="$HOME"

# Sets CHOSEN_IMAGE to the image to apply, or to nothing when the current one is kept.
# $1: value from .env, $2: what is being chosen. Without a value in .env, a file chooser
# opens; without a graphical display, the path is typed in the terminal.
choose_image() {
    local configured=$1 what=$2 status=0
    CHOSEN_IMAGE=""
    if [ -n "$configured" ]; then
        CHOSEN_IMAGE="${configured/#\~/$HOME}"
        return 0
    fi
    if [ ! -t 0 ]; then
        echo -e "${C_YELLOW}No terminal to ask on.${C_RESET}"
        return 0
    fi
    if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
        ensure_command zenity
        echo "Choose the $what in the window that opened (Cancel keeps the current one)."
        CHOSEN_IMAGE="$(zenity --file-selection --title="Choose the $what" --filename="$PICTURES_DIR/" \
            --file-filter="Images | *.jpg *.jpeg *.png *.webp *.avif *.heic *.jxl *.svg *.JPG *.JPEG *.PNG *.HEIC" \
            --file-filter="All files | *" 2> /dev/null)" || status=$?
        # 0: chosen, 1: Cancel. Anything else means the window did not open.
        if [ "$status" -eq 0 ] || [ "$status" -eq 1 ]; then
            return 0
        fi
        echo -e "${C_YELLOW}The file chooser did not open (zenity status $status). Type the path instead.${C_RESET}"
    fi
    # -e: Tab completes the path
    read -r -e -p "Path to the $what (Enter keeps the current one): " CHOSEN_IMAGE || true
    CHOSEN_IMAGE="${CHOSEN_IMAGE/#\~/$HOME}"
}

# Opens $1 the way GNOME does and fails with a message if it is not an image. With $2, also
# writes there the user picture: the centered square as a 512x512 PNG, the size GNOME
# Settings saves (AccountsService refuses pictures over 1 MB).
load_image() {
    python3 - "$@" << 'EOF'
import sys
import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, GLib

try:
    image = GdkPixbuf.Pixbuf.new_from_file(sys.argv[1]).apply_embedded_orientation()
except GLib.Error as error:
    # The first line names the file and the reason; the rest is loader output
    sys.exit(f"Cannot open as an image. {error.message.splitlines()[0]}")
if len(sys.argv) > 2:
    side = min(image.get_width(), image.get_height())
    square = image.new_subpixbuf((image.get_width() - side) // 2, (image.get_height() - side) // 2, side, side)
    square.scale_simple(512, 512, GdkPixbuf.InterpType.HYPER).savev(sys.argv[2], "png", [], [])
EOF
}

# $1: image, $2: .env key it may come from
check_image_file() {
    if [ ! -f "$1" ]; then
        echo -e "${C_RED}Image not found: $1 (check $2 in .env or the path you chose).${C_RESET}" >&2
        exit 1
    fi
}

# ─── Wallpaper ────────────────────────────────────────────────────────────────
print_header "Wallpaper"

# Only-missing mode: a wallpaper you chose (the key is set, not at its default) is kept
CHOSEN_IMAGE=""
if only_missing && [ -n "$(dconf read /org/gnome/desktop/background/picture-uri)" ]; then
    keep_existing "your wallpaper"
else
    choose_image "${WALLPAPER_IMAGE:-}" "wallpaper"
    if [ -z "$CHOSEN_IMAGE" ]; then
        echo -e "${C_YELLOW}Keeping the current wallpaper.${C_RESET}"
    fi
fi
if [ -n "$CHOSEN_IMAGE" ]; then
    check_image_file "$CHOSEN_IMAGE" WALLPAPER_IMAGE
    load_image "$CHOSEN_IMAGE" || exit 1

    # Like GNOME Settings, keep a copy in ~/.local/share/backgrounds, so the wallpaper survives
    # the original being moved or deleted. The content hash in the name lets reruns reuse it.
    BG_DIR="$HOME/.local/share/backgrounds"
    source_image="$(realpath "$CHOSEN_IMAGE")"
    if [[ "$source_image" == "$BG_DIR"/* ]]; then
        wallpaper="$source_image"
    else
        name="$(basename "$source_image")"
        stem="${name%.*}"
        hash="$(sha256sum "$source_image" | cut -c1-8)"
        wallpaper="$BG_DIR/$stem-$hash${name#"$stem"}"
        if [ ! -f "$wallpaper" ]; then
            mkdir -p "$BG_DIR"
            cp "$source_image" "$wallpaper"
        fi
    fi

    uri="$(python3 -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).as_uri())' "$wallpaper")"
    # The same keys GNOME Settings sets: light and dark style, and the lock screen
    gsettings set org.gnome.desktop.background picture-uri "$uri"
    gsettings set org.gnome.desktop.background picture-uri-dark "$uri"
    gsettings set org.gnome.desktop.background picture-options zoom
    gsettings set org.gnome.desktop.screensaver picture-uri "$uri"
    echo -e "${C_GREEN}Wallpaper set: $wallpaper${C_RESET}"
fi

# ─── User picture ─────────────────────────────────────────────────────────────
print_header "User picture"

# AccountsService keeps the picture, shown on the login screen, the lock screen and the
# system menu. Users may change their own picture without sudo.
user_path="$(busctl --system call org.freedesktop.Accounts /org/freedesktop/Accounts \
    org.freedesktop.Accounts FindUserByName s "$USER")"
# Reply format: o "/org/freedesktop/Accounts/User1000"
user_path="${user_path#o \"}"
user_path="${user_path%\"}"
# Reply format: s "/var/lib/AccountsService/icons/<user>" (empty without a picture)
icon_file="$(busctl --system get-property org.freedesktop.Accounts "$user_path" org.freedesktop.Accounts.User IconFile)"
icon_file="${icon_file#s \"}"
icon_file="${icon_file%\"}"

CHOSEN_IMAGE=""
if only_missing && [ -n "$icon_file" ] && [ -f "$icon_file" ]; then
    keep_existing "your user picture"
else
    choose_image "${AVATAR_IMAGE:-}" "user picture"
    if [ -z "$CHOSEN_IMAGE" ]; then
        echo -e "${C_YELLOW}Keeping the current user picture.${C_RESET}"
    fi
fi
if [ -n "$CHOSEN_IMAGE" ]; then
    check_image_file "$CHOSEN_IMAGE" AVATAR_IMAGE
    avatar="$(mktemp --suffix=.png)"
    trap 'rm -f "$avatar"' EXIT
    load_image "$CHOSEN_IMAGE" "$avatar" || exit 1
    busctl --system call org.freedesktop.Accounts "$user_path" \
        org.freedesktop.Accounts.User SetIconFile s "$avatar"
    echo -e "${C_GREEN}User picture set from $CHOSEN_IMAGE.${C_RESET}"
fi
