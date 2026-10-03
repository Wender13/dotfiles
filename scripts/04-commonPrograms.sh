#!/bin/bash
# MENU_DESC: Install common programs
# CATEGORY: PROGRAMS
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro

print_header "Installing common programs"

if is_apt; then
    print_header "Removing LibreOffice and GNOME bloatware"
    # On Ubuntu, metapackages such as ubuntu-desktop depend on some of these. Removing one
    # would take the metapackage along, and a later 'apt autoremove' would strip the desktop.
    # So each installed package is simulated first and kept if apt would remove anything
    # beyond this list.
    mapfile -t bloatware < <(dpkg-query -W -f='${Package} ${db:Status-Status}\n' \
        'libreoffice*' yelp gnome-tour malcontent malcontent-gui gnome-contacts simple-scan 2>/dev/null \
        | awk '$2 == "installed" { print $1 }')
    removable=()
    for pkg in "${bloatware[@]}"; do
        # grep exits 1 when nothing beyond the list would be removed, which is the good case
        extra="$(apt-get -s remove "$pkg" | awk '/^Remv /{ print $2 }' \
            | grep -vxF -f <(printf '%s\n' "${bloatware[@]}") || true)"
        if [ -z "$extra" ]; then
            removable+=("$pkg")
        else
            echo -e "${C_YELLOW}Keeping $pkg: removing it would also remove $(echo "$extra" | tr '\n' ' ')${C_RESET}"
        fi
    done
    if [ ${#removable[@]} -gt 0 ]; then
        sudo apt-get remove -y --purge "${removable[@]}"
    else
        echo -e "${C_YELLOW}Nothing to remove.${C_RESET}"
    fi

    sudo apt update

    # ─── Categorias de Pacotes (Ubuntu/Debian) ───
    CLI_TOOLS="zsh git fzf btop bat zoxide tldr curl wget"
    GUI_APPS="gnome-tweaks vlc tilix gimp obs-studio"
    DEV_TOOLS="make cmake build-essential libssl-dev"
    DATABASES="mariadb-server sqlite3 postgresql"
    CONTAINERS="podman flatpak gnome-software-plugin-flatpak"
    LANGUAGES="python3 python3-pip default-jdk maven"
    CODECS="libavcodec-extra fonts-powerline"
    # ubuntu-restricted-extras only exists on Ubuntu and its derivatives. It pulls the
    # Microsoft core fonts installer, whose EULA dialog would block an unattended run,
    # so the acceptance is preseeded.
    if [[ " ${ID:-} ${ID_LIKE:-} " == *" ubuntu "* ]]; then
        echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" \
            | sudo debconf-set-selections
        CODECS+=" ubuntu-restricted-extras"
    fi

    # shellcheck disable=SC2086  # word splitting is intentional: one transaction
    sudo apt install -y $CLI_TOOLS $GUI_APPS $DEV_TOOLS $DATABASES $CONTAINERS $LANGUAGES $CODECS

elif is_dnf; then
    print_header "Removing LibreOffice and GNOME bloatware"
    # Only installed packages reach dnf, so reruns are no-ops and real failures stay visible.
    # 'malcontent' itself is kept: gnome-control-center (and so gnome-shell) depends on it.
    # Its GUI, malcontent-control, is safe to remove.
    mapfile -t bloatware < <(rpm -qa --qf '%{NAME}\n' 'libreoffice*' yelp gnome-tour malcontent-control gnome-contacts simple-scan | sort -u)
    if [ ${#bloatware[@]} -gt 0 ]; then
        sudo dnf remove -y "${bloatware[@]}"
    else
        echo -e "${C_YELLOW}Nothing to remove.${C_RESET}"
    fi

    print_header "Enabling RPM Fusion"
    if ! rpm -q rpmfusion-free-release rpmfusion-nonfree-release &>/dev/null; then
        fedora_version="$(rpm -E %fedora)"
        sudo dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm" \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm"
    else
        echo -e "${C_YELLOW}RPM Fusion already enabled.${C_RESET}"
    fi

    print_header "Installing multimedia codecs"
    # RPM Fusion howto: the full ffmpeg replaces ffmpeg-free and the libav*-free libraries.
    sudo dnf install -y --allowerasing ffmpeg
    sudo dnf install -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin

    print_header "Installing DNF Packages"

    # ─── Categorias de Pacotes (Fedora) ───
    # Fedora ships Flatpak support inside gnome-software (no separate plugin package).
    CLI_TOOLS="zsh git fzf btop bat eza zoxide tldr curl wget"
    GUI_APPS="gnome-tweaks vlc tilix gimp obs-studio"
    DEV_TOOLS="make cmake gcc gcc-c++ openssl-devel @development-tools"
    DATABASES="mariadb-server sqlite postgresql-server"
    CONTAINERS="podman flatpak"
    LANGUAGES="python3 python3-pip java-25-openjdk-devel java-latest-openjdk-devel maven"
    FONTS="powerline-fonts"

    # shellcheck disable=SC2086  # word splitting is intentional: one transaction
    sudo dnf install -y $CLI_TOOLS $GUI_APPS $DEV_TOOLS $DATABASES $CONTAINERS $LANGUAGES $FONTS
fi

ensure_flathub

echo -e "${C_GREEN}Programs installed.${C_RESET}"
