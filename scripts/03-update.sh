#!/bin/bash
# MENU_DESC: Update system and packages
# CATEGORY: SYSTEM
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro

print_header "Updating system and packages"

# One command per line: a failure inside an '&&' chain would not stop the script.
if is_apt; then
    sudo apt update
    sudo apt upgrade -y
    sudo apt dist-upgrade -y
    sudo apt autoremove -y
elif is_dnf; then
    sudo dnf upgrade --refresh -y
    sudo dnf autoremove -y
fi

if command -v flatpak &>/dev/null; then
    print_header "Updating Flatpak applications"
    sudo flatpak update -y
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
