#!/bin/bash
# MENU_DESC: External repos: VSCode, Chrome, Docker, etc
# CATEGORY: PROGRAMS
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro

ensure_command curl curl curl
ensure_command wget wget wget

# Only-missing mode: an existing repository file is kept as it is (it may have been edited
# or disabled on purpose). Returns 0 when the file may be written.
may_write() {
    if only_missing && [ -f "$1" ]; then
        keep_existing "$1"
        return 1
    fi
}

# Whether Docker Engine was already installed before this run (see the service setup below)
docker_preinstalled=0
if installed_package docker-ce > /dev/null; then
    docker_preinstalled=1
fi

if is_apt; then
    print_header "Installing external repositories (Ubuntu/Debian)"
    sudo install -m 0755 -d /etc/apt/keyrings

    # VSCode
    if may_write /etc/apt/sources.list.d/vscode.list; then
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/packages.microsoft.gpg > /dev/null
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
    fi

    # Vendor repositories are split by base distribution. UBUNTU_CODENAME also covers
    # Ubuntu derivatives (Mint, Pop!_OS), whose own VERSION_CODENAME is not a vendor suite.
    if [[ " ${ID:-} ${ID_LIKE:-} " == *" ubuntu "* ]]; then
        apt_base="ubuntu"
        apt_suite="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
        mongo_component="multiverse"
    else
        apt_base="debian"
        apt_suite="${VERSION_CODENAME:-}"
        mongo_component="main"
    fi

    # MongoDB 8.0. The server is not published for every release: Debian 13 (trixie) only gets
    # mongosh and the tools, so a release without the server uses the bookworm build, which
    # runs on Debian 13 (as Fedora uses the RHEL 9 one). Offline, bookworm is assumed.
    # (The index is read in full first: grep -q in a pipe could cut curl off mid-download.)
    mongo_suite="$apt_suite"
    if [ "$apt_base" = "debian" ]; then
        mongo_index="$(curl -fsS "https://repo.mongodb.org/apt/debian/dists/$apt_suite/mongodb-org/8.0/main/binary-amd64/Packages" 2> /dev/null)" || mongo_index=""
        if ! grep -qx 'Package: mongodb-org' <<< "$mongo_index"; then
            mongo_suite="bookworm"
        fi
    fi
    if may_write /etc/apt/sources.list.d/mongodb-org-8.0.list; then
        curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | sudo gpg --yes --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/$apt_base $mongo_suite/mongodb-org/8.0 $mongo_component" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list > /dev/null
    fi

    # Google Chrome
    if may_write /etc/apt/sources.list.d/google-chrome.list; then
        wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --yes --dearmor -o /usr/share/keyrings/google-chrome.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
    fi

    # Docker
    if may_write /etc/apt/sources.list.d/docker.list; then
        sudo curl -fsSL "https://download.docker.com/linux/$apt_base/gpg" -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$apt_base $apt_suite stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi

    packages=(code mongodb-org mongodb-mongosh google-chrome-stable
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)

    sudo apt-get update
    install_packages "06 - repositorios externos" "${packages[@]}"

    # Docker Desktop is only distributed as a standalone package
    if ! dpkg -s docker-desktop &>/dev/null; then
        echo "Baixando Docker Desktop..."
        desktop_pkg="$(mktemp --suffix=.deb)"
        wget -qO "$desktop_pkg" "https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb"
        sudo apt-get install -y "$desktop_pkg"
        rm -f "$desktop_pkg"
    else
        echo -e "${C_YELLOW}Docker Desktop already installed (it updates itself from its own Settings).${C_RESET}"
    fi

elif is_dnf; then
    print_header "Installing packages via external repositories (Fedora)"

    # dnf5 'config-manager' comes from dnf5-plugins (dnf-plugins-core is the dnf4 one).
    # fedora-workstation-repositories ships the (disabled) Google Chrome repo.
    install_missing_packages dnf5-plugins fedora-workstation-repositories

    # VSCode via Microsoft RPM repo
    if may_write /etc/yum.repos.d/vscode.repo; then
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" \
            | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
    fi

    # MongoDB Server 8.0 via official repo (RHEL 9 build; MongoDB has no Fedora repo)
    if may_write /etc/yum.repos.d/mongodb-org-8.0.repo; then
        echo -e "[mongodb-org-8.0]\nname=MongoDB Repository\nbaseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/8.0/x86_64/\ngpgcheck=1\nenabled=1\ngpgkey=https://pgp.mongodb.com/server-8.0.asc" \
            | sudo tee /etc/yum.repos.d/mongodb-org-8.0.repo > /dev/null
    fi

    # Google Chrome. Only-missing mode: once Chrome is installed, the repository state is yours.
    if only_missing && installed_package google-chrome-stable > /dev/null; then
        keep_existing "the google-chrome repository state"
    else
        sudo dnf config-manager setopt google-chrome.enabled=1
    fi

    # Docker ('addrepo' refuses to overwrite an existing file)
    if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
        sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
    fi

    packages=(code mongodb-org mongodb-mongosh google-chrome-stable
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)

    install_packages "06 - repositorios externos" "${packages[@]}"

    # Docker Desktop is only distributed as a standalone RPM
    if ! rpm -q docker-desktop &>/dev/null; then
        echo "Baixando Docker Desktop..."
        desktop_pkg="$(mktemp --suffix=.rpm)"
        wget -qO "$desktop_pkg" "https://desktop.docker.com/linux/main/amd64/docker-desktop-x86_64.rpm"
        sudo dnf install -y "$desktop_pkg"
        rm -f "$desktop_pkg"
    else
        echo -e "${C_YELLOW}Docker Desktop already installed (it updates itself from its own Settings).${C_RESET}"
    fi
fi

print_header "Enabling Docker Engine"
# Only-missing mode: a Docker that was already installed keeps its service state and group
# members (both may be off on purpose); a Docker installed now is set up as usual.
if only_missing && [ "$docker_preinstalled" -eq 1 ]; then
    keep_existing "the docker service state and group members"
else
    sudo systemctl enable --now docker

    if ! getent group docker > /dev/null; then
        sudo groupadd docker
    fi
    if ! id -nG "$USER" | grep -qw docker; then
        sudo usermod -aG docker "$USER"
        echo -e "${C_YELLOW}Added $USER to the docker group. Log out and back in to use docker without sudo.${C_RESET}"
    fi
fi

echo -e "${C_GREEN}External repos and software installed.${C_RESET}"
