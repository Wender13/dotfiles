---
description: Padrões de código Bash e diretrizes de desenvolvimento para IAs
trigger: always_on
---

# Padrões de Código e Diretrizes (Para IAs e Devs)

Sempre que modificar ou criar um novo script neste repositório, você **deve** seguir as regras abaixo.

## 1. Tratamento Rigoroso de Erros (Fail-Fast)
Todo script modular dentro de `scripts/` DEVE iniciar com:
```bash
#!/bin/bash
set -euo pipefail
```
Isso garante que falhas de rede (como falhas num `wget` ou `git clone`) ou variáveis não inicializadas parem o script imediatamente, sem mascarar erros, e permite que o `app.sh` lide com a falha via `exec_footer`.

- **Proibido usar `|| true` para esconder erro.** Só é aceitável quando a falha é esperada e tratada logo em seguida (ex: `read ... || true` seguido de validação do valor), sempre com o motivo claro no código.
- **Não encadeie comandos críticos com `&&`.** Com `set -e`, uma falha no meio de `a && b && c` NÃO aborta o script. Use um comando por linha.
- Variáveis opcionais devem usar expansão com padrão (`${VAR:-}`), por causa do `set -u`.

## 2. Idempotência Obrigatória
Se o usuário rodar qualquer módulo 5 vezes seguidas, não pode haver erros, duplicação de configurações nem perda de dados. Rodar de novo deve completar o que ficou faltando numa execução interrompida.
- **Ao criar diretórios**: use `mkdir -p`.
- **Ao clonar repositórios**: use `clone_if_missing`.
- **Ao adicionar linhas a arquivos**: use `grep -q` antes do append, ou substitua a chave se ela já existir.
- **Ao instalar pacotes**: use `install_packages` (ou `install_missing_packages`), que pula os instalados. Para downloads avulsos, instaladores externos e passos caros, cheque antes: `rpm -q`, `dpkg -s`, `command -v`, `compgen -G "padrao*"` ou a existência do diretório de destino.
- **Flatpak**: use `install_flatpaks`.
- **Arquivos de repositório**: o `dnf config-manager addrepo` falha se o arquivo já existe; cheque antes.
- **Backups de arquivos de sistema**: crie só uma vez (`[ ! -f arquivo.bak ]`), para nunca sobrescrever o original.
- **Arquivos do usuário**: antes de sobrescrever um arquivo diferente do versionado (ex: `~/.zshrc`), faça backup com data.

## 2.1. Política de Versões (o que já está instalado)
Nunca atualize em silêncio algo que já está instalado: versões novas podem quebrar configurações, plugins e projetos. Toda atualização passa pela política (`ask`, `update` ou `keep`, ver `02-architecture.md`).
- **Pacotes**: `install_packages "titulo" pacotes...`. Nunca rode `dnf upgrade`/`apt upgrade` sem passar por `confirm_updates` (o `dnf install` do dnf5 não atualiza o que já está instalado). Pacotes que precisam de opções especiais (`--allowerasing`, grupos) podem ser instalados direto; junte os nomes num array e ofereça as versões novas no fim com `offer_package_upgrades`, numa única pergunta por módulo (ex: `OFFER` nos módulos 04 e 09).
- **Flatpaks**: `install_flatpaks apps...`. **Clones git** (plugins, temas, forks): `offer_git_updates "titulo" pastas...`.
- **Demais casos** (linguagens, instaladores próprios, temas e fontes baixados): descubra a versão atual e a nova, compare com `version_gt` e chame `confirm_updates "titulo" "nome atual -> nova"` antes de atualizar. Para o que não informa a própria versão, grave o que foi instalado com `record_version` e compare com `recorded_version`.
- **Uma pergunta por grupo**: junte as linhas de um mesmo grupo numa só chamada. Linguagens (Rust, Node, pnpm, uv) são perguntadas uma a uma.
- **Rede**: consultas de versão nunca podem abortar o módulo. Use `var="$(comando)" || var=""` e trate o vazio como "não foi possível verificar", mantendo o que está instalado.
- **Ferramentas que se atualizam sozinhas** (Claude Code, Antigravity CLI, Docker Desktop): apenas informe que já estão instaladas.

## 2.2. Modo Completar (`--only-missing`)
O modo `missing` serve para máquinas já configuradas em parte: instalar e configurar só o que falta, sem estragar o que o usuário já tem. Todo passo novo deve respeitá-lo:
- **Instalar o que falta** funciona igual nos dois modos (as funções do `lib.sh` já pulam o que existe).
- **Remover** (pacotes, arquivos): só no modo `full`. No `missing`, `keep_existing "..."` e nada é removido.
- **Sobrescrever arquivos** (configurações do usuário, arquivos de repositório): no `missing`, só crie o arquivo se ele não existir.
- **Chaves de configuração** (git, dconf/gsettings): no `missing`, grave só as que ainda não foram definidas (`git config --get` vazio, `dconf read` vazio). Listas que o projeto precisa completar (ex: `enabled-extensions`) são mescladas, respeitando o que o usuário desativou.
- **Ajustes que sempre têm valor** (shell padrão, GRUB, tela de boot, papel de parede, serviços, grupos): no `missing`, mantenha o atual, exceto quando o software dono do ajuste foi instalado na mesma execução (guarde o estado antes de instalar, como `docker_preinstalled` no 06 e `zsh_preinstalled` no 08).
- Use `if only_missing && <já existe>; then keep_existing "..."; else <passo normal>; fi`. A política de versões padrão do `missing` é `keep`.
- Teste os dois modos (`DOTFILES_CONFIG_MODE=full` e `missing`) com os falsos da seção 7, comparando o que cada um faria.

## 3. Modularidade e o `lib.sh`
- **Não reinvente a roda**: use `detect_distro`, `is_apt`/`is_dnf`/`is_debian`, `admin_group`/`has_sudo_access`, `ensure_command`, `clone_if_missing`, `load_env`, `ensure_flathub` e as funções da política de versões (ver `02-architecture.md`). Lógica usada por mais de um módulo deve ir para o `lib.sh`.
- **Feedback Visual**: não use `echo` seco para dar títulos a tarefas. Use `print_header "Minha Tarefa"` e as variáveis de cor (`$C_GREEN` para sucesso, `$C_YELLOW` para avisos e passos pulados, `$C_RED` para erros).
- **Evitar Sudo Desnecessário**: os módulos rodam como usuário normal (o `lib.sh` bloqueia root). Use `sudo` APENAS nas linhas que exigem (instalar pacotes, editar `/etc`, serviços).

## 4. Manipulação de Caminhos
NUNCA use caminhos dependentes do diretório atual (ex: `cat ./arquivo.txt`) nem grave arquivos temporários no diretório atual.
- Use `$SCRIPT_DIR` (calculado no módulo) e `$DOTFILES_DIR` (fornecido pelo `lib.sh`):
```bash
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib.sh"
cp "$DOTFILES_DIR/terminal/.zshrc" "$HOME/.zshrc"
```
- Use `"$HOME"` em vez de `~` dentro de aspas e `/home/$USER`.
- Arquivos e diretórios temporários: `mktemp` / `mktemp -d`, com limpeza (`trap ... EXIT` ou `rm -f`).
- Para entrar num diretório, use subshell `( cd "$dir" && ./install.sh )`, para não alterar o diretório do resto do script.

## 5. Compatibilidade com o Modo Headless (`--all`)
- Nenhum passo pode exigir interação se o dado estiver disponível no `.env`. Prompts (`read -r -p`) só como alternativa quando o valor não foi configurado.
- A única senha pedida fora do sudo é a de root, no módulo 00, quando o usuário ainda não tem sudo. Ela nunca vai para o `.env` nem para o código: o `su` a pede direto no terminal.
- Perguntas sobre versões só via `confirm_updates`: ela respeita a política e nunca pergunta com `keep`/`update` ou sem terminal.
- Instaladores de terceiros devem receber argumentos que evitem menus interativos ou TUI (ex: o instalador do tema GRUB abre um `dialog` quando roda sem argumentos).
- Comandos com confirmação usam `-y`. Prefira `sudo usermod --shell` a `chsh`, que pede senha própria.
- Instaladores de toolchains não devem editar arquivos do shell (`--no-modify-path`, `UV_NO_MODIFY_PATH=1`, `--skip-shell`): o `.zshrc` do repositório é a fonte do PATH.
- Quando o instalador oficial não tem opção para isso (ex: `pnpm setup` e `agy install`, que sempre editam o perfil), rode-o com um `HOME` descartável (`env HOME="$(mktemp -d)"`) e aponte o binário para o destino real (`PNPM_HOME`, `--dir`). Teste num `HOME` isolado que o `.zshrc` continua idêntico.

## 6. Como Adicionar Novos Passos
Quando uma IA for solicitada a "adicionar um novo passo na automação", ela deve:
1. Criar o novo script em `scripts/NN-nome.sh` (o número define a posição no menu e no `--all` e é o número que se digita no menu, então não pode repetir; nome com no máximo 24 caracteres, incluindo `.sh`).
2. Incluir o cabeçalho de metadados e o preâmbulo padrão:
   ```bash
   #!/bin/bash
   # MENU_DESC: Descricao curta (max. 44 caracteres)
   # CATEGORY: SECAO
   set -euo pipefail

   SCRIPT_DIR="$(dirname "$(realpath "$0")")"
   source "$SCRIPT_DIR/lib.sh"
   detect_distro
   ```
   Um módulo que só configura o GNOME chama `require_gnome` logo depois do `detect_distro`.
3. Escrever a lógica idempotente, com o ramo `dnf` seguindo `06-fedora.md`, as etapas do GNOME protegidas por `gnome_only` (seção 8) e o modo completar respeitado (seção 2.2).
4. Dar permissão de execução (`chmod +x`), para o git registrar o modo `100755`.
5. Não é preciso editar o `app.sh`: o menu descobre o módulo pelo cabeçalho.
6. Atualizar a tabela de módulos em `02-architecture.md` e no `README.md`. Se o módulo ler uma nova chave do `.env`, adicioná-la ao `.env.example`.
7. Rodar a validação da seção 7.

## 7. Validação Obrigatória Antes de Entregar
NUNCA execute os módulos reais no sistema do usuário para testar: eles instalam pacotes, alteram `/etc` e o bootloader. Valide assim:
1. **Verificações estáticas**: `bash tools/check.sh` (deve terminar em "All checks passed"). Cobre sintaxe (`bash -n`, `zsh -n`), shellcheck (local ou via podman), convenções dos módulos (cabeçalhos, limites de 24/44 caracteres, preâmbulo, permissão de execução, proteção do GNOME, prefixos numéricos sem repetição), largura do menu, caminhos do `$HOME` e emojis.
2. **Comportamento interativo** (Ctrl+C, prompts): teste num pseudo-terminal real (ex: `pty.fork()` do Python). Processos em segundo plano de um shell não interativo herdam o SIGINT ignorado, o que invalida testes de Ctrl+C feitos com `&`.
3. **Pacotes dnf** (não exige root): `dnf repoquery --available <pacote>` para cada nome novo e `dnf install --assumeno <lista completa>` para a transação. Para repositórios ainda não configurados: `--repofrompath=<id>,<url> --repo=<id>`.
4. **Remoções** (não exige root): `dnf remove --assumeno <pacotes>` para ver o que mais seria removido.
5. **Flatpak**: `flatpak remote-info flathub <app-id>`.
6. **Módulos sem root** (01, 07, 08): execute com `HOME` e `XDG_CONFIG_HOME` apontando para um diretório temporário, e rode duas vezes para provar a idempotência.
7. **Módulo 11 (GNOME)**: nunca rode `dconf load` na sessão real do usuário para testar. Execute o módulo com `HOME` temporário, `DBUS_SESSION_BUS_ADDRESS` apontando para um socket inexistente e `sudo`/`dconf` falsos no `PATH` (que só registram as chamadas). Valide os `.ini` com `dconf load` real dentro de um container: `podman run --rm -v "$PWD/style/gnome:/mnt/gnome:ro,Z" registry.fedoraproject.org/fedora:44` com `dbus-daemon` e `dconf` instalados e `dbus-run-session`. O módulo 12 segue o mesmo esquema, com `gsettings`, `busctl` e `zenity` falsos (o `zenity` falso devolve um caminho ou o código de saída a testar: 1 é Cancelar); o prompt de caminho é testado em pseudo-terminal.
8. **Ajustes no `tools/check.sh`**: ao criar uma nova convenção verificável, acrescente a checagem lá. O mesmo script roda no CI (Ubuntu): não use `awk` para contar caracteres (o `mawk` do Ubuntu conta bytes) e mantenha o shellcheck na imagem fixa (0.11.0).
9. **Ramo apt**: valide no Debian 13 rodando os módulos num container `docker.io/library/debian:13` com apt real e instalações simuladas (`sudo` falso que acrescenta `-s`; receita completa em `07-debian.md`, seção 5). Para o Ubuntu, `docker.io/library/ubuntu:24.04` com `apt-get install -s` e, para repositórios de fornecedor, o próprio bloco do módulo executado dentro do container antes de simular.
10. **Interface gráfica** (`gui/`): nunca rode módulos reais por ela para testar. Use uma cópia do repositório com módulos falsos (mesmos cabeçalhos, corpo que só imprime) e `sudo` falso no `PATH`, num display sem tela: `gtk4-broadwayd :9` com um `firefox --headless` conectado em `http://127.0.0.1:8089/` (sem cliente o broadway não desenha quadros), `GDK_BACKEND=broadway`, `WAYLAND_DISPLAY` e `DISPLAY` removidos, `DBUS_SESSION_BUS_ADDRESS` apontando para um socket inexistente e `XDG_CONFIG_HOME`/`XDG_DATA_HOME`/`XDG_STATE_HOME` temporários. Sem `WAYLAND_DISPLAY`, o GTK ainda tenta o `wayland-0` e abre a janela na sessão real; para testar "sem display", aponte também `XDG_RUNTIME_DIR` para uma pasta vazia. Para conferir o visual, renderize a janela em PNG (`Gtk.WidgetPaintable` + `Gsk.CairoRenderer`) nos estilos claro e escuro e numa largura de 360 px.
11. **Harness de teste**: ao medir código de saída num pseudo-terminal, colha o processo com espera bloqueante; um `waitpid` com `WNOHANG` que ainda não terminou devolve status 0 e mascara falhas.

## 8. Configurações do GNOME
- **Só no GNOME**: um módulo que só configura o GNOME chama `require_gnome` logo após o preâmbulo. Etapas do GNOME dentro de outros módulos (extensões, temas, apps como GNOME Tweaks e Extension Manager, remoção do bloatware do GNOME) ficam em `if gnome_only "descrição"; then ... fi`. Em outro desktop a etapa é pulada com aviso, nunca com erro. Use `is_gnome` (silencioso) só para decisões cujo aviso já sai em outro ponto (ex: o `sassc` do módulo 10). O `tools/check.sh` falha se um módulo usar `gsettings`, `dconf` ou `gnome-extensions` sem essas funções.
- **Testar fora do GNOME**: rode o módulo com `XDG_CURRENT_DESKTOP=KDE` (e os falsos da seção 7). Com `XDG_CURRENT_DESKTOP=GNOME`, o terminal do agente ainda tem a sessão D-Bus real: sem `DBUS_SESSION_BUS_ADDRESS` apontando para um socket inexistente e `dconf`/`gsettings` falsos, o módulo 11 grava de verdade na sessão do usuário (e o `@HOME@` vira o `HOME` temporário).
- Não edite `style/gnome/dconf/*.ini` nem `extensions.txt` à mão quando a mudança puder ser feita no GNOME e reexportada com `bash style/gnome/bin/export-gnome-settings.sh`.
- Ao incluir uma nova seção do dconf no exportador, confira o conteúdo: o dconf guarda estado da máquina e dados pessoais (histórico de pastas, contas, credenciais de rede como `org/gnome/nm-applet/eap`). Inclua por lista de seções permitidas, nunca o dump inteiro. Os filtros de segredos do exportador (`SECRET_KEY_RE`, `SECRET_VALUE_RE`, `EMAIL_RE`) valem para todas as seções; ao ampliá-los ou mudá-los, teste com um dump sintético contendo segredos falsos (um `dconf` falso no `PATH` que imprime o dump) e confirme que a exportação real não muda.
- Caminhos dentro do `$HOME` devem virar o marcador `@HOME@` (o exportador faz isso e falha se sobrar algum).
