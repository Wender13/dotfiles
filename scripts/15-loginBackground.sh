#!/bin/bash
# MENU_DESC: [BETA] Login screen: blurred wallpaper
# CATEGORY: BETA
# STAGE: beta
# BETA_FUNCTION: Fundo da tela de login (GDM) com o seu papel de parede atual, desfocado e escurecido, no lugar da cor solida (#222226) do GNOME.
# BETA_DOES: Extrai o recurso de tema do GNOME Shell (/usr/share/gnome-shell/gnome-shell-theme.gresource), acrescenta aos CSS gnome-shell-dark.css e gnome-shell-light.css uma regra #lockDialogGroup com a imagem (background-size: cover), embute a imagem no recurso e o recompila com glib-compile-resources.
# BETA_DOES: Substitui com sudo esse arquivo, que pertence ao pacote gnome-shell (gnome-shell-common no Debian), e guarda o original em /var/lib/dotfiles/gnome-shell-theme.gresource.orig.
# BETA_RISK: Arquivo de pacote alterado: 'rpm -V gnome-shell' (ou o debsums) passa a acusa-lo, e cada atualizacao do gnome-shell volta ao original sem aviso; rode este modulo de novo depois.
# BETA_RISK: Um recurso incompleto ou um CSS incompativel com a versao instalada do GNOME Shell pode deixar a tela de login sem estilo ou sem abrir (tela preta). O mesmo arquivo e o tema padrao da sua sessao quando nenhum tema de shell (User Themes) esta ativo.
# BETA_RISK: A montagem do recurso foi validada em containers Fedora 44 e Debian 13, mas o desenho da tela de login com ele nao (o GDM nao roda ali): o primeiro teste e o seu proximo logout.
# BETA_RISK: Feito para o GNOME Shell 50 (Fedora 44) e 48 (Debian 13); recusa versoes cujo CSS nao tenha o seletor #lockDialogGroup. O Ubuntu (gdm-theme.gresource do Yaru) nao e suportado.
# BETA_UNDO: bash scripts/15-loginBackground.sh --restore (devolve o original guardado), ou sudo dnf reinstall gnome-shell (Debian: sudo apt-get install --reinstall gnome-shell-common).
# BETA_UNDO: Tela preta no login: Ctrl+Alt+F3, entre com o seu usuario no terminal e rode um dos comandos acima; depois, sudo systemctl restart gdm.
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro
load_env

require_gnome

RESOURCE="/usr/share/gnome-shell/gnome-shell-theme.gresource"
BACKUP="/var/lib/dotfiles/gnome-shell-theme.gresource.orig"
THEME_PATH="/org/gnome/shell/theme"
# The image's path inside the resource also marks a resource built by this module
MARKER="$THEME_PATH/dotfiles-login-background.jpg"

# (the listing is read whole first: with pipefail, 'gresource | grep -q' can fail when grep
# stops reading early)
ours() {
    local list
    list="$(gresource list "$RESOURCE" 2> /dev/null)" || return 1
    grep -qxF "$MARKER" <<< "$list"
}

# ─── Undo ─────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--restore" ]; then
    print_header "Restoring the original GNOME Shell theme resource"
    if ! ours; then
        echo -e "${C_YELLOW}$RESOURCE is not the one built by this module: nothing to restore.${C_RESET}"
    elif [ ! -f "$BACKUP" ]; then
        echo -e "${C_RED}No saved original at $BACKUP. Reinstall the package: sudo dnf reinstall gnome-shell (Debian: sudo apt-get install --reinstall gnome-shell-common).${C_RESET}" >&2
        exit 1
    else
        sudo install -m 0644 "$BACKUP" "$RESOURCE.dotfiles-new"
        sudo mv -f "$RESOURCE.dotfiles-new" "$RESOURCE"
        echo -e "${C_GREEN}Original restored. The login screen is back to the GNOME default the next time it opens.${C_RESET}"
    fi
    exit 0
elif [ $# -gt 0 ]; then
    echo -e "${C_RED}Unknown option: $1 (only --restore).${C_RESET}" >&2
    exit 2
fi

confirm_beta

print_header "Login screen background (experimental)"

if [ -e /usr/share/gnome-shell/gdm-theme.gresource ]; then
    echo -e "${C_YELLOW}This system styles GDM with gdm-theme.gresource (Ubuntu's Yaru): not supported. Nothing was changed.${C_RESET}"
    exit 0
fi
if [ ! -f /etc/dconf/profile/gdm ] && [ ! -f /usr/share/dconf/profile/gdm ]; then
    echo -e "${C_YELLOW}GDM not found (another display manager?). Nothing was changed.${C_RESET}"
    exit 0
fi
if [ ! -f "$RESOURCE" ]; then
    echo -e "${C_RED}$RESOURCE not found. Nothing was changed.${C_RESET}" >&2
    exit 1
fi

if only_missing && ! ours; then
    # The login screen always has a background; in this mode it stays as it is
    keep_existing "the current login screen background"
    exit 0
fi

ensure_command gresource libglib2.0-bin glib2-devel
ensure_command glib-compile-resources libglib2.0-dev-bin glib2-devel
ensure_gdkpixbuf

# The resource is rebuilt from the package's original: the installed file when it is still
# the original, the saved copy when it is already ours
if ours; then
    if [ ! -f "$BACKUP" ]; then
        echo -e "${C_RED}$RESOURCE was built by this module, but the original is missing from $BACKUP. Restore the package first (see BETA_UNDO).${C_RESET}" >&2
        exit 1
    fi
    original="$BACKUP"
else
    original="$RESOURCE"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src"

mapfile -t entries < <(gresource list "$original")
if ! grep -qxF "$THEME_PATH/gnome-shell-dark.css" < <(printf '%s\n' "${entries[@]}"); then
    echo -e "${C_RED}$original has no gnome-shell-dark.css: unsupported GNOME Shell version. Nothing was changed.${C_RESET}" >&2
    exit 1
fi
for entry in "${entries[@]}"; do
    mkdir -p "$work/src$(dirname "$entry")"
    gresource extract "$original" "$entry" > "$work/src$entry"
done
if ! grep -q '^#lockDialogGroup' "$work/src$THEME_PATH/gnome-shell-dark.css"; then
    echo -e "${C_RED}The GNOME Shell CSS has no #lockDialogGroup rule: unsupported version. Nothing was changed.${C_RESET}" >&2
    exit 1
fi

# ─── Background image ─────────────────────────────────────────────────────────
# The wallpaper of the dark style (the desktop uses prefer-dark), then the light one, then
# WALLPAPER_IMAGE from .env
wallpaper=""
for key in picture-uri-dark picture-uri; do
    uri="$(gsettings get org.gnome.desktop.background "$key")"
    uri="${uri#\'}"
    uri="${uri%\'}"
    if [[ "$uri" == file://* ]]; then
        wallpaper="$uri"
        break
    fi
done
if [ -z "$wallpaper" ] && [ -n "${WALLPAPER_IMAGE:-}" ]; then
    wallpaper="$WALLPAPER_IMAGE"
fi
if [ -z "$wallpaper" ]; then
    echo -e "${C_RED}No wallpaper found. Choose one with 12-wallpaperAndAvatar.sh or set WALLPAPER_IMAGE in .env.${C_RESET}" >&2
    exit 1
fi
if [[ "$wallpaper" == *.xml ]]; then
    echo -e "${C_RED}The wallpaper is a slideshow (.xml), not an image. Choose an image with 12-wallpaperAndAvatar.sh.${C_RESET}" >&2
    exit 1
fi
echo "Wallpaper: $wallpaper"

python3 - "$wallpaper" "$work/src$MARKER" << 'EOF'
import sys

import gi

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, Gio, GLib

source, target = sys.argv[1], sys.argv[2]
path = Gio.File.new_for_uri(source).get_path() if "://" in source else source
try:
    image = GdkPixbuf.Pixbuf.new_from_file(path).apply_embedded_orientation()
except GLib.Error as error:
    sys.exit(f"Could not open the wallpaper {path}: {error.message}")

# 1920 pixels wide is plenty: the login screen scales it to cover the monitor
width = 1920
height = max(1, round(image.get_height() * width / image.get_width()))
def scaled(pixbuf, w, interp):
    return pixbuf.scale_simple(w, max(1, round(height * w / width)), interp)

# Blur: shrink to a few dozen pixels, then grow back in two smooth steps
blurred = scaled(scaled(scaled(image, 48, GdkPixbuf.InterpType.HYPER), 480,
                        GdkPixbuf.InterpType.BILINEAR), width, GdkPixbuf.InterpType.BILINEAR)
# Darken: the blurred image over black at 65% opacity
result = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, width, height)
result.fill(0x000000FF)
blurred.composite(result, 0, 0, width, height, 0, 0, 1, 1, GdkPixbuf.InterpType.BILINEAR, 166)
result.savev(target, "jpeg", ["quality"], ["90"])
EOF

# ─── Rebuilt resource ─────────────────────────────────────────────────────────
for css in gnome-shell-dark.css gnome-shell-light.css; do
    if [ -f "$work/src$THEME_PATH/$css" ]; then
        cat >> "$work/src$THEME_PATH/$css" << EOF

/* dotfiles (15-loginBackground.sh): blurred wallpaper on the login screen */
#lockDialogGroup {
  background: #222226 url("resource://$MARKER");
  background-size: cover;
  background-repeat: no-repeat;
  background-position: center; }
EOF
    fi
done

{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<gresources>'
    echo '  <gresource prefix="/">'
    for entry in "${entries[@]}" "$MARKER"; do
        echo "    <file>${entry#/}</file>"
    done
    echo '  </gresource>'
    echo '</gresources>'
} > "$work/theme.gresource.xml"
glib-compile-resources --sourcedir="$work/src" --target="$work/theme.gresource" "$work/theme.gresource.xml"

# Every original entry plus the image, and the rule in place, before anything is replaced
expected="$(printf '%s\n' "${entries[@]}" "$MARKER" | sort)"
built="$(gresource list "$work/theme.gresource" | sort)"
gresource extract "$work/theme.gresource" "$THEME_PATH/gnome-shell-dark.css" > "$work/check.css"
if [ "$built" != "$expected" ] || ! grep -qF "resource://$MARKER" "$work/check.css"; then
    echo -e "${C_RED}The rebuilt resource failed its check. Nothing was changed.${C_RESET}" >&2
    exit 1
fi

if cmp -s "$work/theme.gresource" "$RESOURCE"; then
    echo -e "${C_YELLOW}The login screen already has this background.${C_RESET}"
    exit 0
fi

# The original is saved whenever the installed file is still the package's: after a
# gnome-shell update, that is the newer original
if ! ours; then
    sudo install -d -m 0755 "$(dirname "$BACKUP")"
    sudo install -m 0644 "$RESOURCE" "$BACKUP"
    echo "Saved the original in $BACKUP"
fi
# Copied next to it and renamed, so the file is never seen half written
sudo install -m 0644 "$work/theme.gresource" "$RESOURCE.dotfiles-new"
sudo mv -f "$RESOURCE.dotfiles-new" "$RESOURCE"

echo -e "${C_GREEN}Login screen background installed. It shows up the next time the login screen opens (log out or restart).${C_RESET}"
echo -e "${C_YELLOW}To undo: bash scripts/15-loginBackground.sh --restore${C_RESET}"
