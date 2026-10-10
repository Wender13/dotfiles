#!/bin/bash
# MENU_DESC: Claude Desktop and Antigravity IDE
# CATEGORY: DESKTOP APPS
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro

# The desktop versions of the AI tools whose CLIs module 09 installs (claude and agy)
ensure_command curl curl curl

me="$(id -un)"
temp_dir=""
cleanup() { if [ -n "$temp_dir" ]; then rm -rf "$temp_dir"; fi; }
trap cleanup EXIT

# Quotes a path for the Exec key of a desktop entry (quoting rule, then string escapes)
desktop_exec_arg() {
    local quoted=$1
    quoted="${quoted//\\/\\\\}"
    quoted="${quoted//\"/\\\"}"
    quoted="${quoted//\`/\\\`}"
    quoted="${quoted//\$/\\\$}"
    quoted="${quoted//\\/\\\\}"
    printf '"%s"' "${quoted//%/%%}"
}

# ─── Claude Desktop ───────────────────────────────────────────────────────────
# Anthropic's official build exists only for Debian-based systems (Debian 12+, Ubuntu 22.04+),
# from its apt repository, so updates arrive with apt and follow the update policy here.
# Fedora has no official package yet: the claude CLI (module 09) covers it.
print_header "Setting up Claude Desktop"

CLAUDE_KEY=/usr/share/keyrings/claude-desktop-archive-keyring.asc
CLAUDE_LIST=/etc/apt/sources.list.d/claude-desktop.list
# Fingerprint published in Anthropic's install guide: a key with another one is refused
CLAUDE_FINGERPRINT=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

if ! is_apt; then
    echo -e "${C_YELLOW}Claude Desktop has no official package for this distribution yet (only Debian and Ubuntu). The claude CLI from module 09 is the official option here.${C_RESET}"
elif ! [[ "$(dpkg --print-architecture)" =~ ^(amd64|arm64)$ ]]; then
    echo -e "${C_YELLOW}Claude Desktop is published for amd64 and arm64 only. Skipping.${C_RESET}"
else
    claude_preinstalled=0
    if installed_package claude-desktop > /dev/null; then
        claude_preinstalled=1
    fi

    # The key and the repository entry are also managed by the package itself: existing
    # files are never overwritten
    if [ ! -f "$CLAUDE_KEY" ]; then
        ensure_command gpg gnupg gnupg2
        temp_dir="$(mktemp -d)"
        curl -fsSL -o "$temp_dir/key.asc" https://downloads.claude.ai/claude-desktop/key.asc
        key_info="$(gpg --show-keys --with-colons "$temp_dir/key.asc")"
        if ! grep -q "^fpr:::::::::$CLAUDE_FINGERPRINT:" <<< "$key_info"; then
            echo -e "${C_RED}The downloaded Claude Desktop key does not have Anthropic's fingerprint ($CLAUDE_FINGERPRINT). Not installed.${C_RESET}" >&2
            exit 1
        fi
        sudo install -m 0644 "$temp_dir/key.asc" "$CLAUDE_KEY"
    fi
    if [ ! -f "$CLAUDE_LIST" ]; then
        echo "deb [arch=amd64,arm64 signed-by=$CLAUDE_KEY] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
            | sudo tee "$CLAUDE_LIST" > /dev/null
    fi
    sudo apt-get update
    install_packages "13 - Claude Desktop" claude-desktop

    # Cowork runs its tasks in a virtual machine and needs the kvm group (Anthropic's guide).
    # Only-missing mode: a Claude Desktop that was already installed keeps your groups as they are.
    if getent group kvm > /dev/null && ! id -nG "$me" | tr ' ' '\n' | grep -qx kvm; then
        if only_missing && [ "$claude_preinstalled" -eq 1 ]; then
            keep_existing "your groups (Cowork needs kvm: sudo usermod -aG kvm $me)"
        else
            sudo usermod -aG kvm "$me"
            echo -e "${C_YELLOW}Added $me to the kvm group for Cowork. It applies on the next login.${C_RESET}"
        fi
    fi
fi

# ─── Antigravity IDE ──────────────────────────────────────────────────────────
# Google publishes the Linux app only as a tarball (the old apt and rpm repositories stopped
# at 1.x), and the tarball does not update itself. It is installed for your user, like the
# CLIs, and the newest version is read from the official download page and offered through
# the update policy.
print_header "Setting up Antigravity IDE"

AG_DIR="$HOME/.local/share/antigravity-ide"
AG_PAGE="https://antigravity.google/download?os=linux"
AG_DESKTOP="$HOME/.local/share/applications/antigravity-ide.desktop"
case "$(uname -m)" in
    x86_64) ag_arch="x64" ;;
    aarch64) ag_arch="arm" ;;
    *) ag_arch="" ;;
esac

# $1: tarball URL, $2: version. A fresh copy replaces the old one (close the IDE first).
install_antigravity() {
    temp_dir="$(mktemp -d)"
    echo "Downloading Antigravity IDE ${2%%-*}..."
    curl -fSL --progress-bar -o "$temp_dir/ide.tar.gz" "$1"
    tar -xzf "$temp_dir/ide.tar.gz" -C "$temp_dir"
    rm -rf "${AG_DIR:?}"
    mkdir -p "$(dirname "$AG_DIR")"
    mv "$temp_dir/Antigravity IDE" "$AG_DIR"
    rm -rf "${temp_dir:?}"
    temp_dir=""
    record_version antigravity-ide "$2"
}

# An empty result means "not installed anywhere"
other_copy="$(command -v antigravity-ide)" || other_copy=""
if [ -z "$ag_arch" ]; then
    echo -e "${C_YELLOW}Antigravity IDE is published for x86_64 and aarch64 only. Skipping.${C_RESET}"
elif [ -n "$other_copy" ] && [ "$(realpath "$other_copy")" != "$AG_DIR/bin/antigravity-ide" ]; then
    echo -e "${C_YELLOW}Antigravity IDE is already installed at $other_copy (not managed by this module).${C_RESET}"
else
    # The tarball link for this machine, or nothing when the page cannot be read. (awk, not
    # head: head would stop reading early and the broken pipe would fail the whole pipeline.)
    ag_url="$(curl -fsSL --compressed "$AG_PAGE" 2> /dev/null \
        | grep -oE "https://edgedl\.me\.gvt1\.com/edgedl/[^\"' <>]+/antigravity/stable/[0-9.]+-[0-9]+/linux-$ag_arch/Antigravity%20IDE\.tar\.gz" \
        | awk 'NR == 1')" || ag_url=""
    ag_version="$(sed -E 's#.*/stable/([0-9.]+-[0-9]+)/.*#\1#' <<< "$ag_url")"

    if [ ! -x "$AG_DIR/antigravity-ide" ]; then
        if [ -z "$ag_url" ]; then
            echo -e "${C_RED}Could not find the Antigravity IDE download on $AG_PAGE (offline, or the page changed).${C_RESET}" >&2
            exit 1
        fi
        install_antigravity "$ag_url" "$ag_version"
    else
        current="$(recorded_version antigravity-ide)"
        if [ -z "$ag_url" ]; then
            echo -e "${C_YELLOW}Antigravity IDE is installed; could not check for a newer version.${C_RESET}"
        elif [ "$current" = "$ag_version" ]; then
            echo -e "${C_YELLOW}Antigravity IDE is installed and up to date (${current%%-*}).${C_RESET}"
        elif confirm_updates "Antigravity IDE (feche o IDE antes)" "antigravity-ide ${current%%-*} -> ${ag_version%%-*}"; then
            install_antigravity "$ag_url" "$ag_version"
        fi
    fi

    # Launcher on the PATH (~/.local/bin, already in the repo .zshrc) and an applications menu
    # entry. The file name matches the app's own desktopName, so GNOME groups its windows; the
    # URL scheme lets the browser hand the sign-in back to the IDE.
    mkdir -p "$HOME/.local/bin" "$(dirname "$AG_DESKTOP")"
    ln -sfn "$AG_DIR/bin/antigravity-ide" "$HOME/.local/bin/antigravity-ide"
    if only_missing && [ -f "$AG_DESKTOP" ]; then
        keep_existing "$AG_DESKTOP"
    else
        cat > "$AG_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Antigravity IDE
Comment=Google Antigravity agentic IDE
Exec=$(desktop_exec_arg "$AG_DIR/antigravity-ide") %F
Icon=$AG_DIR/resources/app/resources/linux/code.png
Terminal=false
StartupNotify=true
StartupWMClass=antigravity-ide
Categories=Development;IDE;
MimeType=x-scheme-handler/antigravity-ide;
EOF
    fi
    # Usually the MimeType above is enough; a default is set only when nothing handles it
    if command -v xdg-mime > /dev/null && [ -z "$(xdg-mime query default x-scheme-handler/antigravity-ide 2> /dev/null)" ]; then
        mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}"
        xdg-mime default antigravity-ide.desktop x-scheme-handler/antigravity-ide
    fi
    echo -e "${C_GREEN}Antigravity IDE: $(recorded_version antigravity-ide | cut -d- -f1) in $AG_DIR (command: antigravity-ide).${C_RESET}"
fi

echo -e "${C_GREEN}Desktop apps set up.${C_RESET}"
