#!/bin/bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")/scripts"

# ─── Colors ──────────────────────────────────────────────────────────────────
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'
C_DIM='\033[2m'

INN=78   # inner box width (box = 80)

# Modules install into $HOME and call sudo only where needed.
if [ "$(id -u)" -eq 0 ]; then
    printf "${C_RED}Do not run this as root or with sudo. Use your normal user.${C_RESET}\n" >&2
    exit 1
fi

# ─── Data ────────────────────────────────────────────────────────────────────
# categories: non-empty string prints a section header before that item.

# ─── Dynamic Module Discovery ─────────────────────────────────────────────────
scripts=()
descriptions=()
categories=()

# Arrays dinâmicos populados lendo o cabeçalho dos scripts (glob já vem ordenado)
for script_file in "$SCRIPT_DIR"/*.sh; do
    base_name=$(basename "$script_file")
    
    # Ignora o lib.sh
    if [ "$base_name" == "lib.sh" ]; then
        continue
    fi

    # Extrai metadados
    desc=$(grep '^# MENU_DESC:' "$script_file" | sed 's/^# MENU_DESC:[[:space:]]*//')
    cat=$(grep '^# CATEGORY:' "$script_file" | sed 's/^# CATEGORY:[[:space:]]*//')

    scripts+=("$base_name")
    descriptions+=("${desc:-Executar módulo $base_name}")
    categories+=("$cat")
done

# ─── Box drawing helpers ──────────────────────────────────────────────────────

# 'i' must be local: _section calls this outside a subshell, inside show_menu's loop
_rpt() { local s="" i; for ((i=0;i<$2;i++)); do s+="$1"; done; printf "%s" "$s"; }

_top()    { printf "${C_BLUE}╭$(_rpt '─' $INN)╮${C_RESET}\n"; }
_bot()    { printf "${C_BLUE}╰$(_rpt '─' $INN)╯${C_RESET}\n"; }
_hsep()   { printf "${C_BLUE}├$(_rpt '─' $INN)┤${C_RESET}\n"; }
_empty()  { printf "${C_BLUE}│${C_RESET}%${INN}s${C_BLUE}│${C_RESET}\n" ""; }

_center() {
    # $1: text (may contain ANSI)  $2: visible char count
    local pad=$(( (INN - $2) / 2 ))
    local rpad=$(( INN - $2 - pad ))
    [ $pad -lt 0 ]  && pad=0
    [ $rpad -lt 0 ] && rpad=0
    printf "${C_BLUE}│${C_RESET}%${pad}s%b%${rpad}s${C_BLUE}│${C_RESET}\n" "" "$1" ""
}

_section() {
    # $1: label text (plain ASCII)
    local label="  $1  "
    local ll=${#label}
    local left=$(( (INN - ll) / 2 ))
    local right=$(( INN - ll - left ))
    printf "${C_BLUE}├"
    _rpt '─' $left
    printf "${C_BOLD}${C_YELLOW}%s${C_RESET}${C_BLUE}" "$label"
    _rpt '─' $right
    printf "┤${C_RESET}\n"
}

# Item row: │  NN   name (24 cols)  description            │
# Fixed cols: 2 + 2 + 3 + 24 + 2 = 33  →  rpad = INN - 33 - len(desc) - 1
_item() {
    local num=$1 name="$2" desc="$3"
    # Longer names (24) or descriptions (44) would push the right border out of the box
    [ ${#name} -gt 24 ] && name="${name:0:21}..."
    [ ${#desc} -gt 44 ] && desc="${desc:0:41}..."
    local name_pad=$((24 - ${#name})); [ $name_pad -lt 0 ] && name_pad=0
    local rpad=$((INN - 33 - ${#desc} - 1));  [ $rpad -lt 0 ] && rpad=0
    printf "${C_BLUE}│${C_RESET}"
    printf "  ${C_CYAN}${C_BOLD}%2d${C_RESET}" "$num"
    printf "   ${C_BOLD}%s${C_RESET}%${name_pad}s" "$name" ""
    printf "  ${C_DIM}%s${C_RESET}" "$desc"
    printf "%${rpad}s " ""
    printf "${C_BLUE}│${C_RESET}\n"
}

# ─── Menu ─────────────────────────────────────────────────────────────────────
show_menu() {
    clear

    local user="$USER"
    local host; host=$(hostname 2>/dev/null)
    local distro; distro=$(grep '^NAME=' /etc/os-release 2>/dev/null | cut -d'"' -f2)
    [ -z "$distro" ] && distro="Linux"

    local info_plain="$user  ·  $host  ·  $distro"
    local info_col="${C_CYAN}${C_BOLD}${user}${C_RESET}${C_DIM}  ·  ${host}  ·  ${distro}${C_RESET}"

    local title="·  D O T F I L E S   S E T U P   M E N U  ·"
    local title_col="${C_BOLD}${C_BLUE}${title}${C_RESET}"

    _top
    _empty
    _center "$title_col"  "${#title}"
    _center "$info_col"   "${#info_plain}"
    _empty

    # Consecutive modules with the same CATEGORY share one section header
    local current_category=""
    for i in "${!scripts[@]}"; do
        if [ -n "${categories[$i]}" ] && [ "${categories[$i]}" != "$current_category" ]; then
            current_category="${categories[$i]}"
            _section "${categories[$i]}"
            _empty
        fi
        _item "$((i+1))" "${scripts[$i]}" "${descriptions[$i]}"
    done

    _empty
    _hsep

    # Quit row — same column layout as _item, name column blank
    local q_rpad=$((INN - 33 - 4 - 1))   # 4 = len("Exit")
    printf "${C_BLUE}│${C_RESET}"
    printf "  ${C_RED}${C_BOLD} q${C_RESET}"
    printf "   %24s  ${C_DIM}Exit${C_RESET}" ""
    printf "%${q_rpad}s " ""
    printf "${C_BLUE}│${C_RESET}\n"

    _bot
    echo ""
}

# ─── Execution UI ─────────────────────────────────────────────────────────────
HEADLESS=0

exec_header() {
    # In headless mode clearing would wipe the output (and scrollback) of the previous modules
    [ "$HEADLESS" -eq 1 ] || clear
    echo ""
    _top
    local msg="> Executing: $1"
    local rpad=$((INN - 2 - ${#msg} - 1)); [ $rpad -lt 0 ] && rpad=0
    printf "${C_BLUE}│${C_RESET}  ${C_YELLOW}${C_BOLD}%s${C_RESET}%${rpad}s ${C_BLUE}│${C_RESET}\n" "$msg" ""
    _bot; echo ""
}

exec_footer() {
    echo ""
    printf "${C_BLUE}%s${C_RESET}\n" "$(_rpt '─' 80)"
    if [ "$1" -eq 0 ]; then
        printf "  ${C_GREEN}${C_BOLD}Done.${C_RESET}\n"
    else
        printf "  ${C_RED}${C_BOLD}Exited with errors (status $1).${C_RESET}\n"
    fi
    printf "${C_BLUE}%s${C_RESET}\n" "$(_rpt '─' 80)"
    echo ""
}

press_enter() {
    printf "  ${C_DIM}Press [Enter] to return to menu...${C_RESET} "
    read -r || exit 0
}

# Asks for the sudo password once and keeps the timestamp alive, so long
# installs in headless mode do not stop midway waiting for it again.
start_sudo_keepalive() {
    sudo -v || exit 1
    while kill -0 "$$" 2>/dev/null; do
        sudo -n -v 2>/dev/null
        sleep 50
    done &
    SUDO_KEEPALIVE_PID=$!
    # On exit, stop the loop and drop the cached sudo credentials, so they do not
    # stay valid for whatever runs in this terminal afterwards.
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null; sudo -k' EXIT
}

usage() {
    cat <<EOF
Usage: ./app.sh [--all | --help]
  (no option)  Interactive menu
  --all        Run every module in order, without the menu (headless)
  --help       Show this help
EOF
}

# ─── Main loop ────────────────────────────────────────────────────────────────
case "${1:-}" in
    ""|--all) ;;
    -h|--help) usage; exit 0 ;;
    *)
        printf "${C_RED}Unknown option: %s${C_RESET}\n" "$1" >&2
        usage >&2
        exit 2
        ;;
esac

# Modo Headless (Não-interativo)
if [[ "${1:-}" == "--all" ]]; then
    HEADLESS=1
    echo -e "${C_BLUE}${C_BOLD}>> Rodando em Modo Headless (--all)${C_RESET}"
    start_sudo_keepalive

    failed=()
    for i in "${!scripts[@]}"; do
        exec_header "${descriptions[$i]}"
        bash "${SCRIPT_DIR}/${scripts[$i]}"
        status=$?
        exec_footer "$status"
        [ "$status" -ne 0 ] && failed+=("${scripts[$i]}")
    done

    if [ ${#failed[@]} -eq 0 ]; then
        echo -e "\n${C_GREEN}${C_BOLD}>> Setup Headless concluido sem erros.${C_RESET}\n"
        exit 0
    fi
    echo -e "\n${C_RED}${C_BOLD}>> Setup Headless concluido com falhas em:${C_RESET}"
    printf "     - %s\n" "${failed[@]}"
    echo ""
    exit 1
fi

# Modo Interativo
while true; do
    show_menu
    printf "  ${C_BOLD}>>${C_RESET}  Choose: "
    if ! read -r choice; then
        echo ""
        exit 0
    fi

    if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
        clear
        printf "\n  ${C_DIM}See you soon!${C_RESET}\n\n"
        exit 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || \
         [ "$choice" -lt 1 ] || [ "$choice" -gt "${#scripts[@]}" ]; then
        printf "\n  ${C_RED}Invalid option.${C_RESET}\n"
        press_enter
        continue
    fi

    index=$((choice - 1))
    script_path="${SCRIPT_DIR}/${scripts[$index]}"

    exec_header "${descriptions[$index]}"

    if [ -f "$script_path" ]; then
        # While the module runs, Ctrl+C stops only the module and comes back to the menu.
        # A handler (not an ignore) keeps the default Ctrl+C behavior inside the module, and it
        # is removed afterwards, so Ctrl+C at the menu prompt still leaves.
        trap ':' INT
        bash "$script_path"
        status=$?
        trap - INT
        exec_footer "$status"
    else
        printf "  ${C_RED}Error: '%s' not found in '%s'.${C_RESET}\n\n" \
            "${scripts[$index]}" "$SCRIPT_DIR"
    fi

    press_enter
done
