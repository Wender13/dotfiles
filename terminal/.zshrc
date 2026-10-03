# ============================================================
#  .zshrc — oh-my-zsh + Spaceship
# ============================================================

# Descomente para medir o tempo de inicialização (e o `zprof` no fim do arquivo)
# zmodload zsh/zprof

# ------------------------------------------------------------
# PATH base
# ------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"

# ------------------------------------------------------------
# oh-my-zsh
# ------------------------------------------------------------
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="spaceship"

# zsh-completions precisa estar no fpath ANTES do source do oh-my-zsh
fpath+=${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-completions/src

# zsh-syntax-highlighting deve ser o último da lista
plugins=(
  git
  k
  zsh-interactive-cd
  zsh-completions
  zsh-autosuggestions
  zsh-syntax-highlighting
)

# ------------------------------------------------------------
# Spaceship — configurar ANTES do source
# ------------------------------------------------------------
SPACESHIP_PROMPT_ORDER=(
  user        # usuário
  host        # /host  (fica colado ao usuário: usuario/host)
  dir         # diretório
  time        # horário logo após o diretório
  git
  node
  ruby
  xcode
  swift
  golang
  php
  rust
  docker
  venv
  line_sep
  char
)

# PROMPT
SPACESHIP_PROMPT_SYMBOL="➜"
SPACESHIP_PROMPT_ADD_NEWLINE=false
SPACESHIP_PROMPT_PREFIXES_SHOW=true
SPACESHIP_PROMPT_SUFFIXES_SHOW=true
SPACESHIP_PROMPT_DEFAULT_PREFIX="via "
SPACESHIP_PROMPT_DEFAULT_SUFFIX=" "

# USER  ->  "com jr"
SPACESHIP_USER_SHOW=always
SPACESHIP_USER_PREFIX="com "
SPACESHIP_USER_SUFFIX=""
SPACESHIP_USER_COLOR="#005fd7"
SPACESHIP_USER_COLOR_ROOT="red"

# HOST  ->  "/nome-da-maquina"  (resultado: com jr/nome-da-maquina)
SPACESHIP_HOST_SHOW=always
SPACESHIP_HOST_PREFIX="/"
SPACESHIP_HOST_SUFFIX="$SPACESHIP_PROMPT_DEFAULT_SUFFIX"
SPACESHIP_HOST_COLOR="#005fd7"
SPACESHIP_HOST_COLOR_SSH="#005fd7"

# DIR
SPACESHIP_DIR_SHOW=true
SPACESHIP_DIR_PREFIX="em "
SPACESHIP_DIR_SUFFIX="$SPACESHIP_PROMPT_DEFAULT_SUFFIX"
SPACESHIP_DIR_TRUNC=3
SPACESHIP_DIR_COLOR="#005fd7"

# TIME  ->  "às 14:32:05"
SPACESHIP_TIME_SHOW=true
SPACESHIP_TIME_PREFIX="às "
SPACESHIP_TIME_SUFFIX="$SPACESHIP_PROMPT_DEFAULT_SUFFIX"
SPACESHIP_TIME_FORMAT="%*"   # escape do zsh: HH:MM:SS (24h). Alternativa: "%D{%H:%M}"
SPACESHIP_TIME_12HR=false
SPACESHIP_TIME_COLOR="#005fd7"

# GIT
SPACESHIP_GIT_SHOW=true
SPACESHIP_GIT_PREFIX="na branch "
SPACESHIP_GIT_SUFFIX="$SPACESHIP_PROMPT_DEFAULT_SUFFIX"
SPACESHIP_GIT_SYMBOL=" "

# GIT BRANCH
SPACESHIP_GIT_BRANCH_SHOW=true
SPACESHIP_GIT_BRANCH_PREFIX="$SPACESHIP_GIT_SYMBOL"
SPACESHIP_GIT_BRANCH_SUFFIX=""
SPACESHIP_GIT_BRANCH_COLOR="magenta"

# GIT STATUS
SPACESHIP_GIT_STATUS_SHOW=true
SPACESHIP_GIT_STATUS_PREFIX=" ["
SPACESHIP_GIT_STATUS_SUFFIX="]"
SPACESHIP_GIT_STATUS_COLOR="red"
SPACESHIP_GIT_STATUS_UNTRACKED="?"
SPACESHIP_GIT_STATUS_ADDED="+"
SPACESHIP_GIT_STATUS_MODIFIED="!"
SPACESHIP_GIT_STATUS_RENAMED="»"
SPACESHIP_GIT_STATUS_DELETED="✘"
SPACESHIP_GIT_STATUS_STASHED="$"
SPACESHIP_GIT_STATUS_UNMERGED="="
SPACESHIP_GIT_STATUS_AHEAD="⇡"
SPACESHIP_GIT_STATUS_BEHIND="⇣"
SPACESHIP_GIT_STATUS_DIVERGED="⇕"

# NODE
SPACESHIP_NODE_SHOW=true
SPACESHIP_NODE_PREFIX="$SPACESHIP_PROMPT_DEFAULT_PREFIX"
SPACESHIP_NODE_SUFFIX="$SPACESHIP_PROMPT_DEFAULT_SUFFIX"
SPACESHIP_NODE_SYMBOL="⬢ "
SPACESHIP_NODE_DEFAULT_VERSION=""
SPACESHIP_NODE_COLOR="green"

# Carrega o oh-my-zsh (depois de plugins, fpath e variáveis do tema)
source "$ZSH/oh-my-zsh.sh"

# ------------------------------------------------------------
# Histórico e opções gerais
# ------------------------------------------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS SHARE_HISTORY

# export EDITOR='nvim'

# ------------------------------------------------------------
# Node (apenas fnm — nvm removido para evitar conflito e lentidão)
# ------------------------------------------------------------
FNM_PATH="$HOME/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
  export PATH="$FNM_PATH:$PATH"
  eval "$(fnm env --use-on-cd --shell zsh)"
fi

# pnpm (o instalador oficial, usado pelo scripts/09, guarda os binarios em $PNPM_HOME/bin)
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PNPM_HOME:$PATH" ;;
esac

# Rust
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$("$HOME/anaconda3/bin/conda" 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="$HOME/anaconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# ============================================================
#  Aliases
# ============================================================
# ll: eza (cores, icones, status do git) quando instalado; senao, o ls
if command -v eza >/dev/null 2>&1; then
  alias ll='eza -lah --git --icons --group-directories-first'
  alias lt='eza --tree --level=2 --icons'   # arvore de 2 niveis
else
  alias ll='ls -lah'
fi
# bat: cat com destaque de sintaxe (use 'bat arquivo'; o cat continua o original)
alias ..='cd ..'
alias ...='cd ../..'
alias zshconfig='${EDITOR:-nano} ~/.zshrc'
alias zshreload='source ~/.zshrc && echo ".zshrc recarregado"'

# ============================================================
#  Funções — DNF / atualização do sistema
# ============================================================

# Atualiza tudo: dnf, limpeza, flatpak (se houver) e avisa se precisa reiniciar
update() {
  echo "==> Atualizando pacotes (dnf)..."
  sudo dnf upgrade --refresh -y || return 1

  echo "==> Removendo pacotes órfãos..."
  sudo dnf autoremove -y

  echo "==> Limpando cache de pacotes..."
  sudo dnf clean packages

  if command -v flatpak >/dev/null 2>&1; then
    echo "==> Atualizando Flatpaks..."
    flatpak update -y
    flatpak uninstall --unused -y
  fi

  echo "==> Verificando se é preciso reiniciar..."
  sudo dnf needs-restarting -r 2>/dev/null || echo "Reinicie o sistema para aplicar as atualizações."

  echo "==> Concluído."
}

# Buscar pacote:            dnfs firefox
dnfs()    { dnf search "$@"; }
# Instalar pacote(s):       dnfi vim git
dnfi()    { sudo dnf install "$@"; }
# Remover pacote(s):        dnfr vim
dnfr()    { sudo dnf remove "$@"; }
# Informações do pacote:    dnfinfo git
dnfinfo() { dnf info "$@"; }
# Qual pacote fornece:      dnfp /usr/bin/convert
dnfp()    { dnf provides "$@"; }
# Listar instalados:        dnfl [filtro]
dnfl()    { if [ -n "$1" ]; then dnf list installed | grep -i -- "$1"; else dnf list installed; fi; }
# Histórico de transações:  dnfh
dnfh()    { sudo dnf history "$@"; }

# ============================================================
#  Funções — Git
# ============================================================

# Add + commit de tudo:       gcommit "mensagem"
gcommit() {
  if [ -z "$1" ]; then echo "Uso: gcommit \"mensagem\""; return 1; fi
  git add -A && git commit -m "$*"
}

# Add + commit + push:        gship "mensagem"
gship() {
  if [ -z "$1" ]; then echo "Uso: gship \"mensagem\""; return 1; fi
  git add -A && git commit -m "$*" && git push -u origin HEAD
}

# Push da branch atual (cria upstream se necessário)
gpush() { git push -u origin HEAD "$@"; }

# Cria e troca para nova branch:  gnew feature/x
gnew() {
  if [ -z "$1" ]; then echo "Uso: gnew nome-da-branch"; return 1; fi
  git switch -c "$1"
}

# Busca tudo, poda remotas e atualiza com rebase
gsync() { git fetch --all --prune && git pull --rebase; }

# Desfaz o último commit mantendo as alterações no stage
gundo() { git reset --soft HEAD~1; }

# Adiciona tudo ao último commit sem mudar a mensagem
gfix() { git add -A && git commit --amend --no-edit; }

# Log em grafo:               glogp [quantidade]
glogp() { git log --graph --oneline --decorate --all -n "${1:-20}"; }

# Apaga branches locais já mergeadas (gclean já é alias do plugin git) (preserva main/master/develop e a atual)
gprune() {
  git fetch --prune
  git branch --merged | grep -Ev '(^\*|^\+|^\s*(main|master|develop)$)' | xargs -r git branch -d
}

# Guarda alterações rapidamente:   gsave  /  recupera com: git stash pop
gsave() { git add -A && git stash push -m "WIP $(date +%F_%H:%M)"; }

# ------------------------------------------------------------
# zoxide: 'z <parte do nome>' pula para pastas ja visitadas; 'zi' escolhe com fzf.
# Fica no fim do arquivo, depois do compinit do oh-my-zsh, como pede o zoxide.
# ------------------------------------------------------------
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

# ------------------------------------------------------------
# Descomente junto com o zmodload no topo para ver o profiling
# zprof
