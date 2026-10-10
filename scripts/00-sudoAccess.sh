#!/bin/bash
# MENU_DESC: Give your user sudo and log access
# CATEGORY: ENVIRONMENT
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro

# Every other module calls sudo. When a root password is set during the Debian
# installation, the first user is left out of the sudo group (and sudo itself may be
# missing), so this module uses su, with the root password, once. It only adds: no group
# membership is ever removed, so it behaves the same in the only-missing mode.
print_header "Setting up administrator access"

me="$(id -un)"
ADMIN_GROUP="$(admin_group)"
# The admin group, plus adm and systemd-journal to read the system logs without sudo
WANTED_GROUPS=("$ADMIN_GROUP" adm systemd-journal)

missing_groups=()
for group in "${WANTED_GROUPS[@]}"; do
    if ! getent group "$group" > /dev/null; then
        continue
    fi
    # The group database, not this session: a group added earlier is already there
    if ! id -nG "$me" | tr ' ' '\n' | grep -qx "$group"; then
        missing_groups+=("$group")
    fi
done

root_commands=()
done_parts=()
if ! command -v sudo > /dev/null; then
    done_parts+=("sudo installed")
    if is_dnf; then
        root_commands+=("dnf install -y sudo")
    else
        root_commands+=("apt-get update" "DEBIAN_FRONTEND=noninteractive apt-get install -y sudo")
    fi
fi
if [ ${#missing_groups[@]} -gt 0 ]; then
    root_commands+=("usermod -aG $(IFS=,; echo "${missing_groups[*]}") $me")
    done_parts+=("$me added to: ${missing_groups[*]}")
fi
summary="$(printf '%s, ' "${done_parts[@]}")"
summary="${summary%, }"

if [ ${#root_commands[@]} -eq 0 ]; then
    echo -e "${C_YELLOW}$me already has sudo and can read the logs (groups: ${WANTED_GROUPS[*]}).${C_RESET}"
elif has_sudo_access; then
    # Only the log groups are missing: sudo is enough
    for command in "${root_commands[@]}"; do
        sudo sh -c "$command"
    done
    echo -e "${C_GREEN}Done: $summary.${C_RESET}"
else
    if [ ! -t 0 ]; then
        echo -e "${C_RED}$me cannot use sudo yet, and setting it up needs the root password. Run this module from a terminal, or as root: ${root_commands[*]}${C_RESET}" >&2
        exit 1
    fi
    echo "$me cannot use sudo yet. As root, this will run:"
    printf '    %s\n' "${root_commands[@]}"
    echo -e "${C_BOLD}Type the ROOT password (not yours) when su asks for it.${C_RESET}"
    # One su call, so the root password is asked only once; set -e stops at the first failure
    su --login root --command "set -e; $(printf '%s; ' "${root_commands[@]}")"
    echo -e "${C_GREEN}Done: $summary.${C_RESET}"
fi

# Group changes only reach new logins
if ! has_sudo_access; then
    echo -e "${C_YELLOW}Log out and back in (or run 'newgrp $ADMIN_GROUP' in this terminal) before running the other modules: this session does not have the $ADMIN_GROUP group yet.${C_RESET}"
fi
