#!/bin/bash
# MENU_DESC: [BETA] Login screen layout (8 options)
# CATEGORY: BETA
# STAGE: beta
# BETA_FUNCTION: Tela inicial do login (lista de usuarios) com hora e data em um de oito layouts: painel cobrindo metade da tela (panel-right, panel-left), cartao numa das metades (card-right, card-left), faixa num terco da tela (band-bottom, band-top) ou so o relogio acima ou abaixo do usuario (clock-above, clock-below). O relogio do topo some enquanto a lista aparece; a etapa da senha continua a padrao do GNOME.
# BETA_FUNCTION: Cada escolha vem da opcao na linha de comando (--layout, --style, --blur, --darkness; --help lista todas), senao do .env, senao de um menu numerado no terminal (Enter mantem o valor atual; no ./app.sh --all nao pergunta), senao do valor ja instalado.
# BETA_FUNCTION: Painel, cartao e faixa podem ser de vidro (LOGIN_PANEL_STYLE=glass: desfoca o que esta atras, com LOGIN_PANEL_BLUR de 0 a 100) ou solidos (solid); LOGIN_PANEL_DARKNESS (0 a 100) diz o quanto escurecem. Padrao na primeira vez: panel-right, glass, 40 e 45.
# BETA_DOES: Instala com sudo a extensao login-layout@wender13.github.io (style/gnome/gdm-extension, com o schema compilado por glib-compile-schemas) em /usr/share/gnome-shell/extensions, com "session-modes": ["gdm"], o que a faz rodar so na tela de login.
# BETA_DOES: Ativa a extensao e grava o layout no banco dconf do GDM (enabled-extensions e org/gnome/shell/extensions/login-layout em /etc/dconf/db/gdm.d/96-dotfiles-login-layout com dconf update; no Debian, em /usr/share/gdm/dconf com generate-config). Nenhum arquivo de pacote e alterado.
# BETA_DOES: A extensao desloca a lista de usuarios (translation_x/translation_y), poe hora e data atras do dialogo (para os botoes do GNOME ficarem por cima), aplica o Shell.BlurEffect no modo BACKGROUND no vidro e esconde o relogio do painel, usando objetos internos do dialogo de login (Main.screenShield._dialog._userSelectionBox).
# BETA_RISK: Esses objetos internos podem mudar entre versoes do GNOME Shell: se sumirem, a extensao nao faz nada e a tela fica a padrao; um erro nela faz o GNOME desativa-la, sem impedir o login. Ela declara as versoes 48 a 50 e o GNOME a ignora nas outras.
# BETA_RISK: Os oito layouts foram vistos rodando o GNOME Shell 50 em modo de tela de login num container; no 48 (Debian 13) foram conferidos so pelo codigo-fonte. O vidro so aparece com algo atras para desfocar (o fundo do modulo 15); sem ele, parece solido.
# BETA_RISK: Em monitor estreito (retrato) as partes podem se sobrepor; em varios monitores, o layout vale para o principal.
# BETA_UNDO: bash scripts/16-loginLayout.sh --restore (remove a extensao e as chaves do GDM). Para trocar de layout, mude o .env e rode o modulo de novo.
# BETA_UNDO: Tela de login quebrada: Ctrl+Alt+F3, entre com o seu usuario no terminal, rode o comando acima e depois sudo systemctl restart gdm.
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro
load_env

UUID="login-layout@wender13.github.io"
SOURCE="$DOTFILES_DIR/style/gnome/gdm-extension/$UUID"
TARGET="/usr/share/gnome-shell/extensions/$UUID"

# "name|description", in menu order: the same choices as the extension's settings schema
LAYOUTS=(
    "panel-right|Painel cobrindo a metade direita; usuario no centro da esquerda"
    "panel-left|Painel cobrindo a metade esquerda; usuario no centro da direita"
    "card-right|Cartao com hora e data na metade direita; usuario na esquerda"
    "card-left|Cartao com hora e data na metade esquerda; usuario na direita"
    "band-bottom|Faixa no terco de baixo da tela; usuario acima"
    "band-top|Faixa no terco de cima da tela; usuario abaixo"
    "clock-above|So o relogio, acima do usuario, sem painel"
    "clock-below|So o relogio, abaixo do usuario, sem painel"
)
STYLES=(
    "glass|Vidro: desfoca o que esta atras (o fundo do modulo 15), sob um tom escuro"
    "solid|Solido: cor opaca, o fundo da tela de login escurecido"
)

usage() {
    cat << EOF
Usage: bash scripts/16-loginLayout.sh [--layout NAME] [--style glass|solid] [--blur 0-100] [--darkness 0-100]
       bash scripts/16-loginLayout.sh --restore | --help

Each choice comes from its option, else from .env (LOGIN_LAYOUT, LOGIN_PANEL_STYLE,
LOGIN_PANEL_BLUR, LOGIN_PANEL_DARKNESS), else from a menu (on a terminal, except in
./app.sh --all), else it keeps the installed value (first time: panel-right, glass, 40, 45).

Layouts (--layout, LOGIN_LAYOUT):
$(for entry in "${LAYOUTS[@]}"; do printf '  %-12s %s\n' "${entry%%|*}" "${entry#*|}"; done)

Panel, card and band style (--style, LOGIN_PANEL_STYLE):
$(for entry in "${STYLES[@]}"; do printf '  %-12s %s\n' "${entry%%|*}" "${entry#*|}"; done)

  --blur      blur radius of the glass, in pixels (0 to 100)
  --darkness  how dark the panel is, in percent (0 to 100; for the solid one, 100 is black)
  --restore   remove the extension and its settings from the login screen
EOF
}

# ─── Options ──────────────────────────────────────────────────────────────────
RESTORE=0
FLAG_LAYOUT=""
FLAG_STYLE=""
FLAG_BLUR=""
FLAG_DARKNESS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --restore) RESTORE=1 ;;
        -h|--help)
            usage
            exit 0
            ;;
        --layout|--style|--blur|--darkness)
            if [ $# -lt 2 ]; then
                echo -e "${C_RED}$1 needs a value.${C_RESET}" >&2
                usage >&2
                exit 2
            fi
            case "$1" in
                --layout) FLAG_LAYOUT="$2" ;;
                --style) FLAG_STYLE="$2" ;;
                --blur) FLAG_BLUR="$2" ;;
                --darkness) FLAG_DARKNESS="$2" ;;
            esac
            shift
            ;;
        *)
            echo -e "${C_RED}Unknown option: $1${C_RESET}" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

require_gnome

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
if [ "$RESTORE" -eq 1 ]; then
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

# ─── Choices ──────────────────────────────────────────────────────────────────
# Value of a key in the installed settings (quotes removed), or nothing
installed_setting() {
    if [ -f "$GDM_SETTINGS" ]; then
        sed -n "s/^$1=//p" "$GDM_SETTINGS" | tr -d "'"
    fi
}

# Numbered menu of "name|description" entries. $1: title, $2: current name, then the entries.
# Takes a number or a name; Enter keeps the current one. Sets CHOICE.
choose() {
    local title=$1 current=$2 entry name mark answer i=1
    shift 2
    echo -e "\n${C_BOLD}$title${C_RESET}"
    for entry in "$@"; do
        name="${entry%%|*}"
        mark=""
        if [ "$name" = "$current" ]; then
            mark="  (atual)"
        fi
        printf '  %d) %-12s %s%s\n' "$i" "$name" "${entry#*|}" "$mark"
        i=$((i + 1))
    done
    while true; do
        # Ctrl+D counts as Enter (keep the current one)
        read -r -p "  Numero ou nome [Enter mantem $current]: " answer || answer=""
        if [ -z "$answer" ]; then
            CHOICE="$current"
            return
        fi
        if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le $# ]; then
            entry="${!answer}"
            CHOICE="${entry%%|*}"
            return
        fi
        for entry in "$@"; do
            if [ "${entry%%|*}" = "$answer" ]; then
                CHOICE="$answer"
                return
            fi
        done
        echo -e "${C_YELLOW}  Opcao invalida.${C_RESET}"
    done
}

# A whole number from 0 to 100. $1: question, $2: current value. Sets CHOICE.
choose_number() {
    local answer
    while true; do
        read -r -p "  $1 (0 a 100) [Enter mantem $2]: " answer || answer=""
        if [ -z "$answer" ]; then
            CHOICE="$2"
            return
        fi
        if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -le 100 ]; then
            CHOICE="$answer"
            return
        fi
        echo -e "${C_YELLOW}  Use um numero de 0 a 100.${C_RESET}"
    done
}

# The choices set so far (an option or .env may hold anything); empty ones are not set yet
check_choices() {
    local key name
    if [ -n "$LOGIN_LAYOUT" ] && ! grep -qxF -- "$LOGIN_LAYOUT" <<< "$(printf '%s\n' "${LAYOUTS[@]%%|*}")"; then
        echo -e "${C_RED}Invalid layout '$LOGIN_LAYOUT' (see --help). Nothing was changed.${C_RESET}" >&2
        exit 1
    fi
    if [ -n "$LOGIN_PANEL_STYLE" ] && [ "$LOGIN_PANEL_STYLE" != "glass" ] && [ "$LOGIN_PANEL_STYLE" != "solid" ]; then
        echo -e "${C_RED}Invalid panel style '$LOGIN_PANEL_STYLE' (glass or solid). Nothing was changed.${C_RESET}" >&2
        exit 1
    fi
    for key in LOGIN_PANEL_BLUR LOGIN_PANEL_DARKNESS; do
        name="${key#LOGIN_PANEL_}"
        if [ -n "${!key}" ] && { ! [[ "${!key}" =~ ^[0-9]+$ ]] || [ "${!key}" -gt 100 ]; }; then
            echo -e "${C_RED}Invalid ${name,,} '${!key}' (a whole number from 0 to 100). Nothing was changed.${C_RESET}" >&2
            exit 1
        fi
    done
}

# Option, then .env; what is still missing is asked on a terminal (not in ./app.sh --all,
# confirmed at its start to run unattended) or keeps the installed value
LOGIN_LAYOUT="${FLAG_LAYOUT:-${LOGIN_LAYOUT:-}}"
LOGIN_PANEL_STYLE="${FLAG_STYLE:-${LOGIN_PANEL_STYLE:-}}"
LOGIN_PANEL_BLUR="${FLAG_BLUR:-${LOGIN_PANEL_BLUR:-}}"
LOGIN_PANEL_DARKNESS="${FLAG_DARKNESS:-${LOGIN_PANEL_DARKNESS:-}}"
# Wrong values are refused before any question
check_choices
current_layout="$(installed_setting layout)"
current_style="$(installed_setting panel-style)"
current_blur="$(installed_setting panel-blur)"
current_darkness="$(installed_setting panel-darkness)"
ask=0
if [ -t 0 ] && [ "${DOTFILES_BETA_CONFIRMED:-}" != "1" ]; then
    ask=1
fi
if [ -z "$LOGIN_LAYOUT" ]; then
    LOGIN_LAYOUT="${current_layout:-panel-right}"
    if [ "$ask" -eq 1 ]; then
        choose "Layout da tela de login" "$LOGIN_LAYOUT" "${LAYOUTS[@]}"
        LOGIN_LAYOUT="$CHOICE"
    fi
fi
# The clock-only layouts have no panel: nothing else to ask
if [[ "$LOGIN_LAYOUT" == clock-* ]]; then
    ask=0
fi
if [ -z "$LOGIN_PANEL_STYLE" ]; then
    LOGIN_PANEL_STYLE="${current_style:-glass}"
    if [ "$ask" -eq 1 ]; then
        choose "Estilo do painel" "$LOGIN_PANEL_STYLE" "${STYLES[@]}"
        LOGIN_PANEL_STYLE="$CHOICE"
    fi
fi
if [ -z "$LOGIN_PANEL_BLUR" ]; then
    LOGIN_PANEL_BLUR="${current_blur:-40}"
    # Only the glass is blurred
    if [ "$ask" -eq 1 ] && [ "$LOGIN_PANEL_STYLE" = "glass" ]; then
        echo ""
        choose_number "Desfoque do vidro, em pixels" "$LOGIN_PANEL_BLUR"
        LOGIN_PANEL_BLUR="$CHOICE"
    fi
fi
if [ -z "$LOGIN_PANEL_DARKNESS" ]; then
    LOGIN_PANEL_DARKNESS="${current_darkness:-45}"
    if [ "$ask" -eq 1 ]; then
        choose_number "Escuridao do painel, em %" "$LOGIN_PANEL_DARKNESS"
        LOGIN_PANEL_DARKNESS="$CHOICE"
    fi
fi

check_choices
echo -e "\nLayout: $LOGIN_LAYOUT, panel: $LOGIN_PANEL_STYLE (blur $LOGIN_PANEL_BLUR, darkness $LOGIN_PANEL_DARKNESS%)"

ensure_command dconf dconf-cli dconf
ensure_command glib-compile-schemas libglib2.0-bin glib2

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# ─── Extension files ──────────────────────────────────────────────────────────
# The repository's version with its settings schema compiled (it changes with the repository,
# like module 14's settings)
cp -R "$SOURCE" "$work/$UUID"
glib-compile-schemas --strict "$work/$UUID/schemas"
if [ -d "$TARGET" ] && diff -rq "$work/$UUID" "$TARGET" &> /dev/null; then
    echo -e "${C_YELLOW}The login screen extension is up to date.${C_RESET}"
else
    sudo rm -rf -- "$TARGET"
    sudo install -d -m 0755 "$(dirname "$TARGET")"
    sudo cp -R --preserve=mode "$work/$UUID" "$TARGET"
    echo "Installed $UUID in $(dirname "$TARGET")"
fi

# ─── Enabled and configured on the login screen ───────────────────────────────
settings="$work/settings"
cat > "$settings" << EOF
# Login screen layout extension, enabled and configured by 16-loginLayout.sh (.env)
[org/gnome/shell]
enabled-extensions=['$UUID']

[org/gnome/shell/extensions/login-layout]
layout='$LOGIN_LAYOUT'
panel-style='$LOGIN_PANEL_STYLE'
panel-blur=$LOGIN_PANEL_BLUR
panel-darkness=$LOGIN_PANEL_DARKNESS
EOF
if [ -f "$GDM_SETTINGS" ] && cmp -s "$settings" "$GDM_SETTINGS"; then
    echo -e "${C_YELLOW}Already enabled and configured on the login screen.${C_RESET}"
else
    sudo install -D -m 0644 "$settings" "$GDM_SETTINGS"
    gdm_dconf_update "$GDM_DIR"
    echo "Enabled and configured on the login screen ($GDM_SETTINGS)"
fi

echo -e "${C_GREEN}Login screen layout installed ($LOGIN_LAYOUT). It shows up the next time the login screen opens (log out or restart).${C_RESET}"
echo -e "${C_YELLOW}To undo: bash scripts/16-loginLayout.sh --restore${C_RESET}"
