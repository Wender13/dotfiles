#!/bin/bash
# MENU_DESC: Configure terminal and shell
# CATEGORY:
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
detect_distro

print_header "Setting up ZSH and Oh My Zsh"

ensure_command zsh zsh zsh
ensure_command git git git
ensure_command curl curl curl

clone_if_missing https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

print_header "Installing plugins"

clone_if_missing https://github.com/supercrabtree/k                          "${ZSH_CUSTOM}/plugins/k"
clone_if_missing https://github.com/zsh-users/zsh-autosuggestions             "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting.git     "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
clone_if_missing https://github.com/zsh-users/zsh-completions                 "${ZSH_CUSTOM}/plugins/zsh-completions"

print_header "Installing Spaceship theme"

clone_if_missing https://github.com/spaceship-prompt/spaceship-prompt.git "${ZSH_CUSTOM}/themes/spaceship-prompt"
ln -sfn "${ZSH_CUSTOM}/themes/spaceship-prompt/spaceship.zsh-theme" \
        "${ZSH_CUSTOM}/themes/spaceship.zsh-theme"

# Already cloned ones: newer upstream commits follow the update policy
offer_git_updates "Zsh: oh-my-zsh, plugins e tema" \
    "$HOME/.oh-my-zsh" \
    "${ZSH_CUSTOM}/plugins/k" \
    "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" \
    "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" \
    "${ZSH_CUSTOM}/plugins/zsh-completions" \
    "${ZSH_CUSTOM}/themes/spaceship-prompt"

print_header "Installing Nerd Fonts"

FONT_DIR="$HOME/.local/share/fonts/NerdFonts"
NERD_FONTS=(JetBrainsMono FiraCode)
# Latest release tag (e.g. v3.5.1), read from the redirect of the "latest" page.
# Empty when offline: the check is skipped instead of aborting the module.
nf_latest="$(curl -fsSI https://github.com/ryanoasis/nerd-fonts/releases/latest | sed -n 's#^location: .*/tag/##ip' | tr -d '\r')" || nf_latest=""

# $1: font name, $2: release tag ("latest" when the tag is unknown)
install_nerd_font() {
    local url archive
    if [ "$2" = "latest" ]; then
        url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$1.tar.xz"
    else
        url="https://github.com/ryanoasis/nerd-fonts/releases/download/$2/$1.tar.xz"
    fi
    echo "Downloading $1 Nerd Font..."
    mkdir -p "$FONT_DIR"
    # The .tar.xz assets are about 15x smaller than the .zip ones
    archive="$(mktemp --suffix=.tar.xz)"
    curl -fsSL -o "$archive" "$url"
    tar -xJf "$archive" -C "$FONT_DIR" --wildcards '*.ttf'
    rm -f "$archive"
}

fonts_changed=0
missing_fonts=()
for font in "${NERD_FONTS[@]}"; do
    if ! compgen -G "$FONT_DIR/${font}NerdFont-*" > /dev/null; then
        missing_fonts+=("$font")
    fi
done
if [ ${#missing_fonts[@]} -gt 0 ]; then
    for font in "${missing_fonts[@]}"; do
        install_nerd_font "$font" "${nf_latest:-latest}"
    done
    fonts_changed=1
    # The recorded version is only trusted when every font came from the same release
    if [ ${#missing_fonts[@]} -eq ${#NERD_FONTS[@]} ] && [ -n "$nf_latest" ]; then
        record_version nerd-fonts "$nf_latest"
    fi
else
    nf_current="$(recorded_version nerd-fonts)"
    if [ -z "$nf_latest" ]; then
        echo -e "${C_YELLOW}Nerd Fonts installed; could not check for a newer release.${C_RESET}"
    elif [ "$nf_current" != "$nf_latest" ]; then
        if confirm_updates "Nerd Fonts" "${NERD_FONTS[*]} $nf_current -> $nf_latest"; then
            for font in "${NERD_FONTS[@]}"; do
                install_nerd_font "$font" "$nf_latest"
            done
            record_version nerd-fonts "$nf_latest"
            fonts_changed=1
        fi
    else
        echo -e "${C_YELLOW}Nerd Fonts installed and up to date ($nf_current).${C_RESET}"
    fi
fi

if [ "$fonts_changed" -eq 1 ]; then
    echo "Updating font cache..."
    fc-cache -f "$FONT_DIR" > /dev/null
fi

print_header "Setting ZSH as default shell"

zsh_path="$(command -v zsh)"
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh_path" ]; then
    # usermod through sudo avoids chsh's own password prompt (keeps --all unattended)
    sudo usermod --shell "$zsh_path" "$USER"
    echo -e "${C_YELLOW}Default shell changed. It applies on the next login.${C_RESET}"
else
    echo -e "${C_YELLOW}ZSH is already the default shell.${C_RESET}"
fi

# Fix for bat on Ubuntu
if is_apt; then
    mkdir -p "$HOME/.local/bin"
    ln -sf /usr/bin/batcat "$HOME/.local/bin/bat"
fi

print_header "Copying .zshrc"

if [ -f "$HOME/.zshrc" ] && ! cmp -s "$DOTFILES_DIR/terminal/.zshrc" "$HOME/.zshrc"; then
    backup="$HOME/.zshrc.bak.$(date +%Y%m%d%H%M%S)"
    cp "$HOME/.zshrc" "$backup"
    echo -e "${C_YELLOW}Existing .zshrc differs from the repo version. Backup saved to $backup${C_RESET}"
fi
cp "$DOTFILES_DIR/terminal/.zshrc" "$HOME/.zshrc"

echo -e "${C_GREEN}ZSH setup complete.${C_RESET}"
