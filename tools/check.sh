#!/bin/bash
# Static checks for the whole project. Safe to run at any time: it never executes a module,
# never calls sudo and never touches the system configuration.
#
# Usage: bash tools/check.sh
# Package names and dnf transactions still need the manual checks described in
# .agents/rules/03-standards.md (dnf repoquery / dnf install --assumeno).
set -uo pipefail   # no -e: every check runs and all failures are reported

# The menu and the emoji check count characters, not bytes: force a UTF-8 locale
export LC_ALL=C.UTF-8

ROOT="$(realpath "$(dirname "$(realpath "$0")")/..")"
cd "$ROOT" || exit 1

failures=0
fail() { echo "  FAIL  $1"; failures=$((failures + 1)); }
ok()   { echo "  ok    $1"; }

SHELL_FILES=(app.sh scripts/*.sh style/gnome/bin/*.sh tools/*.sh)
MODULES=()
for f in scripts/[0-9][0-9]-*.sh; do MODULES+=("$f"); done

echo "Syntax"
syntax_ok=1
for f in "${SHELL_FILES[@]}"; do
    bash -n "$f" 2>/dev/null || { fail "bash -n $f"; syntax_ok=0; }
done
if command -v zsh &>/dev/null; then
    zsh -n terminal/.zshrc 2>/dev/null || { fail "zsh -n terminal/.zshrc"; syntax_ok=0; }
fi
# The graphical interface: parsed only (no GTK needed, no __pycache__ written in the repo)
for f in gui/*.py; do
    python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$f" 2>/dev/null \
        || { fail "python syntax $f"; syntax_ok=0; }
done
[ "$syntax_ok" -eq 1 ] && ok "bash -n on ${#SHELL_FILES[@]} files, zsh -n on terminal/.zshrc, python on gui/"

echo "Lint (shellcheck, warnings and errors)"
SC_ARGS=(-x -S warning -e SC1091 -e SC2034)
# Pinned image: shellcheck versions report different warnings, so local runs and CI use the same one
SC_IMAGE="docker.io/koalaman/shellcheck:v0.11.0"
container_tool=""
command -v podman &>/dev/null && container_tool=podman
[ -z "$container_tool" ] && command -v docker &>/dev/null && container_tool=docker
if [ -n "$container_tool" ]; then
    "$container_tool" run --rm -v "$ROOT:/mnt:ro,Z" -w /mnt "$SC_IMAGE" "${SC_ARGS[@]}" "${SHELL_FILES[@]}" \
        && ok "shellcheck 0.11.0 ($container_tool)" || fail "shellcheck (see output above)"
elif command -v shellcheck &>/dev/null; then
    shellcheck "${SC_ARGS[@]}" "${SHELL_FILES[@]}" \
        && ok "shellcheck $(shellcheck --version | sed -n 's/^version: //p') (local; CI uses 0.11.0)" \
        || fail "shellcheck (see output above)"
else
    echo "  skip  no podman, docker or shellcheck available"
fi

echo "Module conventions"
modules_ok=1
for f in "${MODULES[@]}"; do
    name=$(basename "$f")
    desc=$(sed -n 's/^# MENU_DESC:[[:space:]]*//p' "$f" | head -n1)
    [ ${#name} -le 24 ]                          || { fail "$name: file name longer than 24 characters"; modules_ok=0; }
    [ -n "$desc" ]                               || { fail "$name: missing '# MENU_DESC:'"; modules_ok=0; }
    [ ${#desc} -le 44 ]                          || { fail "$name: MENU_DESC longer than 44 characters"; modules_ok=0; }
    grep -q '^# CATEGORY:' "$f"                  || { fail "$name: missing '# CATEGORY:'"; modules_ok=0; }
    grep -q '^set -euo pipefail$' "$f"           || { fail "$name: missing 'set -euo pipefail'"; modules_ok=0; }
    grep -q 'source "$SCRIPT_DIR/lib.sh"' "$f"   || { fail "$name: does not source lib.sh"; modules_ok=0; }
    grep -q '^detect_distro$' "$f"               || { fail "$name: does not call detect_distro"; modules_ok=0; }
    [ -x "$f" ]                                  || { fail "$name: not executable (chmod +x)"; modules_ok=0; }
    # GNOME settings and extensions are applied only on GNOME (require_gnome/gnome_only in lib.sh)
    if grep -qE '(gsettings|dconf|gnome-extensions) ' "$f" && ! grep -qE 'require_gnome|gnome_only|is_gnome' "$f"; then
        fail "$name: changes GNOME settings without require_gnome or gnome_only"; modules_ok=0
    fi
done
[ -x app.sh ] || { fail "app.sh: not executable (chmod +x)"; modules_ok=0; }
[ "$modules_ok" -eq 1 ] && ok "${#MODULES[@]} modules follow the header, preamble, naming and GNOME guard rules"

echo "Menu rendering"
widths=$(printf 'q\n' | TERM=dumb ./app.sh 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | grep -E '^[│╭╰├]' \
    | while IFS= read -r line; do echo "${#line}"; done | sort -u | tr '\n' ' ')
# (bash counts characters; mawk, the default awk on Debian/Ubuntu, would count bytes)
if [ "$widths" = "80 " ]; then
    ok "every menu line is 80 columns wide"
else
    fail "menu lines with unexpected widths: $widths(expected only 80)"
fi

echo "Personal data and style"
data_ok=1
if grep -rIn --exclude-dir=.git -e "/home/$USER" . > /dev/null 2>&1; then
    fail "absolute path of this user's home found:"; grep -rIn --exclude-dir=.git -e "/home/$USER" . | head -5
    data_ok=0
fi
# Emojis are forbidden (the Spaceship prompt glyphs in terminal/.zshrc are terminal symbols, not emojis)
if grep -rInP --exclude-dir=.git --exclude=.zshrc '[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{FE0F}]' . > /dev/null 2>&1; then
    fail "emoji found:"; grep -rInP --exclude-dir=.git --exclude=.zshrc '[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{FE0F}]' . | head -5
    data_ok=0
fi
[ "$data_ok" -eq 1 ] && ok "no home paths of this user and no emojis"

echo
if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed."
    exit 1
fi
echo "All checks passed."
