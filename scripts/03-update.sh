#!/bin/bash
# MENU_DESC: Update system and packages
# CATEGORY: SYSTEM
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro

# This module exists to update, but it still follows the update policy: with "keep" it only
# reports what is available, with "ask" it lists everything and asks once per group.
print_header "Updating system and packages"

# One command per line: a failure inside an '&&' chain would not stop the script.
if is_apt; then
    sudo apt update
    # Lines look like: name/suite 2.0-1 amd64 [upgradable from: 1.0-1]
    mapfile -t system_lines < <(apt list --upgradable 2> /dev/null \
        | awk 'index($0, "[upgradable from:") { split($1, p, "/"); old = $NF; sub(/\]$/, "", old); print p[1], old, "->", $2 }')
elif is_dnf; then
    mapfile -t system_lines < <(dnf repoquery --refresh --upgrades --latest-limit=1 --qf '%{name} %{evr}\n' 2> /dev/null \
        | sort -u | while read -r name new; do
            echo "$name $(rpm -q --qf '%{EVR}\n' "$name" | head -n1) -> $new"
        done)
fi

if [ ${#system_lines[@]} -eq 0 ]; then
    echo "System packages are up to date."
elif confirm_updates "Pacotes do sistema" "${system_lines[@]}"; then
    if is_apt; then
        sudo apt upgrade -y
        sudo apt dist-upgrade -y
        sudo apt autoremove -y
    else
        sudo dnf upgrade --refresh -y
        sudo dnf autoremove -y
    fi
fi

if command -v flatpak &>/dev/null; then
    print_header "Updating Flatpak applications"
    mapfile -t flatpak_lines < <(flatpak remote-ls --system --updates --columns=application,version 2> /dev/null \
        | awk -F'\t' '{ print $1, "->", ($2 == "" ? "nova revisao" : $2) }')
    if [ ${#flatpak_lines[@]} -eq 0 ]; then
        echo "Flatpaks are up to date."
    elif confirm_updates "Flatpak (aplicativos e runtimes)" "${flatpak_lines[@]}"; then
        sudo flatpak update -y
    fi
fi

# ─── Firmware (report only) ───────────────────────────────────────────────────
# Flashing firmware is left as a deliberate step: it may need AC power and a reboot.
# Metadata is refreshed by fwupd's own timer, and --json never prompts.
if command -v fwupdmgr &>/dev/null && command -v python3 &>/dev/null; then
    print_header "Checking firmware updates"
    if fw_json="$(fwupdmgr get-updates --json --no-unreported-check --no-metadata-check 2>/dev/null)" \
        && fw_count="$(python3 -c 'import json, sys; print(len(json.load(sys.stdin).get("Devices", [])))' <<< "$fw_json")"; then
        if [ "$fw_count" -gt 0 ]; then
            echo -e "${C_YELLOW}$fw_count device(s) with firmware updates. Review and apply with: fwupdmgr update${C_RESET}"
        else
            echo "No firmware updates."
        fi
    else
        echo -e "${C_YELLOW}fwupd reported no updatable devices or could not be reached.${C_RESET}"
    fi
fi

# ─── Reboot check ─────────────────────────────────────────────────────────────
print_header "Checking whether a reboot is needed"
if is_dnf; then
    reboot_needed=0
    # Exit status 1 means core packages (kernel, glibc, systemd...) were updated
    dnf needs-restarting -r --cacheonly > /dev/null 2>&1 || reboot_needed=1
elif [ -f /var/run/reboot-required ]; then
    reboot_needed=1
else
    reboot_needed=0
fi
if [ "$reboot_needed" -eq 1 ]; then
    echo -e "${C_YELLOW}Reboot recommended to finish applying the updates.${C_RESET}"
else
    echo "No reboot needed."
fi

echo -e "${C_GREEN}System and packages updated.${C_RESET}"
