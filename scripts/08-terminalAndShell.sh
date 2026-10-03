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

print_header "Installing Nerd Fonts"

FONT_DIR="$HOME/.local/share/fonts/NerdFonts"
fonts_changed=0
for font in JetBrainsMono FiraCode; do
    if compgen -G "$FONT_DIR/${font}NerdFont-*" > /dev/null; then
        echo -e "${C_YELLOW}$font Nerd Font already installed.${C_RESET}"
        continue
    fi
    echo "Downloading $font Nerd Font..."
    mkdir -p "$FONT_DIR"
    # The .tar.xz assets are about 15x smaller than the .zip ones
    archive="$(mktemp --suffix=.tar.xz)"
    curl -fsSL -o "$archive" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.tar.xz"
    tar -xJf "$archive" -C "$FONT_DIR" --wildcards '*.ttf'
    rm -f "$archive"
    fonts_changed=1
done

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
