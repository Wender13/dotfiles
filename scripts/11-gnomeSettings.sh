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

require_gnome

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

# Version published on extensions.gnome.org for this GNOME Shell, or nothing (offline, none)
ego_version() {
    curl -fsS "https://extensions.gnome.org/extension-info/?uuid=$1&shell_version=${SHELL_VERSION}" 2> /dev/null \
        | python3 -c 'import json, sys; print(json.load(sys.stdin)["version"])' 2> /dev/null || true
}

dnf_packages=()
ego_extensions=()
ego_installed=()
# extensions.txt: "[disabled] UUID [Fedora package]" per line; '#' starts a comment.
# Disabled ones are installed the same way: the enabled/disabled lists loaded from
# dconf/shell.ini below keep them off.
while read -r uuid package extra _; do
    if [ "$uuid" = "disabled" ]; then
        uuid="$package"
        package="$extra"
    fi
    if [ -z "$uuid" ] || [[ "$uuid" == \#* ]]; then
        continue
    fi
    if [ -n "$package" ] && is_dnf && [ ! -d "$HOME/.local/share/gnome-shell/extensions/$uuid" ]; then
        # Native package (updated by dnf), unless a user-installed copy already takes precedence
        dnf_packages+=("$package")
    elif [ -d "$HOME/.local/share/gnome-shell/extensions/$uuid" ]; then
        ego_installed+=("$uuid")
    elif extension_installed "$uuid"; then
        echo -e "${C_YELLOW}Already installed (system): $uuid${C_RESET}"
    else
        ego_extensions+=("$uuid")
    fi
done < "$GNOME_DIR/extensions.txt"

if [ ${#dnf_packages[@]} -gt 0 ]; then
    install_packages "Extensoes do GNOME (pacotes do Fedora)" "${dnf_packages[@]}"
fi

# User-installed extensions: newer builds on extensions.gnome.org follow the update policy.
# (GNOME Shell also updates these by itself; this makes the update explicit and immediate.)
ego_lines=()
ego_updates=()
for uuid in "${ego_installed[@]}"; do
    current="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("version", 0))' \
        "$HOME/.local/share/gnome-shell/extensions/$uuid/metadata.json" 2> /dev/null || echo 0)"
    latest="$(ego_version "$uuid")"
    if [ -n "$latest" ] && version_gt "$latest" "$current"; then
        ego_lines+=("$uuid v$current -> v$latest")
        ego_updates+=("$uuid")
    else
        echo -e "${C_YELLOW}Already installed: $uuid (v$current)${C_RESET}"
    fi
done
if confirm_updates "Extensoes do GNOME (extensions.gnome.org)" "${ego_lines[@]}"; then
    ego_extensions+=("${ego_updates[@]}")
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
    if only_missing; then
        # Profiles you already have are kept
        cp --update=none "$GNOME_DIR"/burn-my-windows/profiles/*.conf "$HOME/.config/burn-my-windows/profiles/"
    else
        cp "$GNOME_DIR"/burn-my-windows/profiles/*.conf "$HOME/.config/burn-my-windows/profiles/"
    fi
fi

# ─── Settings ─────────────────────────────────────────────────────────────────
# Desktop, input, power, extension preferences, enabled extensions, dock favorites
# and every shortcut. Loading only sets the listed keys; reruns are harmless.
print_header "Applying GNOME settings and shortcuts"

# Only-missing mode: reads a dconf dump on stdin and keeps only the keys you have not set
# yet ('dconf read' prints nothing for a key still at its default). For enabled-extensions,
# the repository extensions you have neither enabled nor disabled are added to your list.
unset_keys_only() {
    local section="" line key current merged
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[(.*)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            echo "$line"
            continue
        fi
        if [[ "$line" == \#* ]] || [[ "$line" != *=* ]]; then
            echo "$line"
            continue
        fi
        key="${line%%=*}"
        current="$(dconf read "/$section/$key")"
        if [ -z "$current" ]; then
            echo "$line"
        elif [ "$section/$key" = "org/gnome/shell/enabled-extensions" ]; then
            merged="$(python3 - "$current" "${line#*=}" "$(dconf read /org/gnome/shell/disabled-extensions)" <<'EOF'
import ast, sys

def parse(value):
    value = value.strip()
    if value.startswith("@as"):
        value = value[3:].strip()
    return ast.literal_eval(value) if value else []

current, repo, disabled = (parse(v) for v in sys.argv[1:4])
added = [uuid for uuid in repo if uuid not in current and uuid not in disabled]
if added:
    print(repr(current + added))
EOF
)"
            if [ -n "$merged" ]; then
                echo "$key=$merged"
            fi
        fi
    done
}

skipped=0
for ini in "$GNOME_DIR"/dconf/*.ini; do
    echo "Loading $(basename "$ini")..."
    if only_missing; then
        settings="$(sed "s|@HOME@|$HOME|g" "$ini" | unset_keys_only)"
        # grep -c exits 1 when it counts zero lines
        total="$(grep -c '^[^#[].*=' "$ini")" || total=0
        applied="$(grep -c '^[^#[].*=' <<< "$settings")" || applied=0
        skipped=$((skipped + total - applied))
        dconf load / <<< "$settings"
    else
        sed "s|@HOME@|$HOME|g" "$ini" | dconf load /
    fi
done
if only_missing && [ "$skipped" -gt 0 ]; then
    keep_existing "$skipped GNOME setting(s) you had already set"
fi

if [ ${#failed[@]} -gt 0 ]; then
    echo -e "${C_RED}Settings applied, but these extensions were not installed: ${failed[*]}${C_RESET}" >&2
    echo -e "${C_YELLOW}They may not support GNOME Shell $SHELL_VERSION yet. Rerun this module later or use Extension Manager.${C_RESET}" >&2
    exit 1
fi

echo -e "${C_GREEN}GNOME configured. Log out and back in to load newly installed extensions.${C_RESET}"
