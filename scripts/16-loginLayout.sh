#!/bin/bash
# MENU_DESC: [BETA] Login screen: user left, clock right
# CATEGORY: BETA
# STAGE: beta
# BETA_FUNCTION: Tela inicial do login (lista de usuarios) em duas colunas: a caixa com foto e nome a esquerda e uma caixa solida com hora e data a direita; o relogio do topo some enquanto a lista aparece. A etapa da senha continua a padrao do GNOME.
# BETA_DOES: Instala com sudo a extensao login-layout@wender13.github.io (style/gnome/gdm-extension) em /usr/share/gnome-shell/extensions, com "session-modes": ["gdm"], o que a faz rodar so na tela de login.
# BETA_DOES: Ativa a extensao no banco dconf do GDM (enabled-extensions em /etc/dconf/db/gdm.d/96-dotfiles-login-layout com dconf update; no Debian, em /usr/share/gdm/dconf com generate-config). Nenhum arquivo de pacote e alterado.
# BETA_DOES: A extensao desloca a lista de usuarios um quarto da largura do monitor principal (translation_x), cria a caixa do relogio na metade direita e esconde o relogio do painel, usando objetos internos do dialogo de login (Main.screenShield._dialog._userSelectionBox).
# BETA_RISK: Esses objetos internos podem mudar entre versoes do GNOME Shell: se sumirem, a extensao nao faz nada e a tela fica a padrao; um erro nela faz o GNOME desativa-la, sem impedir o login. Ela declara as versoes 48 a 50 e o GNOME a ignora nas outras.
# BETA_RISK: Escrita a partir do codigo do GNOME Shell 50 (Fedora 44) e conferida no 48 (Debian 13). O desenho da tela de login nao pode ser visto aqui: o primeiro teste e o seu proximo logout.
# BETA_RISK: Em monitor estreito (retrato) as duas colunas podem se sobrepor; em varios monitores, o layout vale para o principal.
# BETA_UNDO: bash scripts/16-loginLayout.sh --restore (remove a extensao e a chave do GDM).
# BETA_UNDO: Tela de login quebrada: Ctrl+Alt+F3, entre com o seu usuario no terminal, rode o comando acima e depois sudo systemctl restart gdm.
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro

require_gnome

UUID="login-layout@wender13.github.io"
SOURCE="$DOTFILES_DIR/style/gnome/gdm-extension/$UUID"
TARGET="/usr/share/gnome-shell/extensions/$UUID"

# GDM's own dconf database (see gdm_dconf_dir in lib.sh)
if ! GDM_DIR="$(gdm_dconf_dir)"; then
    echo -e "${C_RED}Unknown GDM dconf layout. Nothing was changed.${C_RESET}" >&2
    exit 1
fi
if [ -z "$GDM_DIR" ]; then
    echo -e "${C_YELLOW}GDM not found (another display manager?). Nothing was changed.${C_RESET}"
    exit 0
fi
GDM_SETTINGS="$GDM_DIR/96-dotfiles-login-layout"

# ─── Undo ─────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--restore" ]; then
    print_header "Removing the login screen layout"
    if [ ! -e "$TARGET" ] && [ ! -f "$GDM_SETTINGS" ]; then
        echo -e "${C_YELLOW}The login screen layout is not installed: nothing to remove.${C_RESET}"
        exit 0
    fi
    if [ -f "$GDM_SETTINGS" ]; then
        sudo rm -f "$GDM_SETTINGS"
        gdm_dconf_update "$GDM_DIR"
    fi
    if [ -e "$TARGET" ]; then
        sudo rm -rf -- "$TARGET"
    fi
    echo -e "${C_GREEN}Removed. The login screen is back to the GNOME default the next time it opens.${C_RESET}"
    exit 0
elif [ $# -gt 0 ]; then
    echo -e "${C_RED}Unknown option: $1 (only --restore).${C_RESET}" >&2
    exit 2
fi

confirm_beta

print_header "Login screen layout (experimental)"

# GNOME skips an extension that does not list the running major version: say so instead
shell_version="$(gnome-shell --version | awk '{ split($3, v, "."); print v[1] }')"
if ! grep -q "\"$shell_version\"" "$SOURCE/metadata.json"; then
    echo -e "${C_RED}GNOME Shell $shell_version is not among the versions this layout was written for (see $SOURCE/metadata.json). Nothing was changed.${C_RESET}" >&2
    exit 1
fi

if only_missing && [ ! -f "$GDM_SETTINGS" ]; then
    # The login screen always has a layout; in this mode it stays as it is
    keep_existing "the current login screen layout"
    exit 0
fi

ensure_command dconf dconf-cli dconf

# ─── Extension files ──────────────────────────────────────────────────────────
# A copy of the repository's version (it changes with the repository, like module 14's settings)
if [ -d "$TARGET" ] && diff -rq "$SOURCE" "$TARGET" &> /dev/null; then
    echo -e "${C_YELLOW}The login screen extension is up to date.${C_RESET}"
else
    sudo rm -rf -- "$TARGET"
    sudo install -d -m 0755 "$(dirname "$TARGET")"
    sudo cp -R --preserve=mode,timestamps "$SOURCE" "$TARGET"
    echo "Installed $UUID in $(dirname "$TARGET")"
fi

# ─── Enabled on the login screen ──────────────────────────────────────────────
settings="$(mktemp)"
trap 'rm -f "$settings"' EXIT
cat > "$settings" << EOF
# Login screen layout extension, enabled by 16-loginLayout.sh
[org/gnome/shell]
enabled-extensions=['$UUID']
EOF
if [ -f "$GDM_SETTINGS" ] && cmp -s "$settings" "$GDM_SETTINGS"; then
    echo -e "${C_YELLOW}Already enabled on the login screen.${C_RESET}"
else
    sudo install -D -m 0644 "$settings" "$GDM_SETTINGS"
    gdm_dconf_update "$GDM_DIR"
    echo "Enabled on the login screen ($GDM_SETTINGS)"
fi

echo -e "${C_GREEN}Login screen layout installed. It shows up the next time the login screen opens (log out or restart).${C_RESET}"
echo -e "${C_YELLOW}To undo: bash scripts/16-loginLayout.sh --restore${C_RESET}"
