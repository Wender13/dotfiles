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
- **Ao instalar pacotes**: o `dnf`/`apt` já ignora pacotes instalados. Para downloads avulsos, instaladores externos e passos caros, cheque antes: `rpm -q`, `dpkg -s`, `command -v`, `compgen -G "padrao*"` ou a existência do diretório de destino.
- **Flatpak**: use `flatpak install -y --or-update`.
- **Arquivos de repositório**: o `dnf config-manager addrepo` falha se o arquivo já existe; cheque antes.
- **Backups de arquivos de sistema**: crie só uma vez (`[ ! -f arquivo.bak ]`), para nunca sobrescrever o original.
- **Arquivos do usuário**: antes de sobrescrever um arquivo diferente do versionado (ex: `~/.zshrc`), faça backup com data.

## 3. Modularidade e o `lib.sh`
- **Não reinvente a roda**: use `detect_distro`, `is_apt`/`is_dnf`, `ensure_command`, `clone_if_missing`, `load_env` e `ensure_flathub` (ver `02-architecture.md`). Lógica usada por mais de um módulo deve ir para o `lib.sh`.
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
- Instaladores de terceiros devem receber argumentos que evitem menus interativos ou TUI (ex: o instalador do tema GRUB abre um `dialog` quando roda sem argumentos).
- Comandos com confirmação usam `-y`. Prefira `sudo usermod --shell` a `chsh`, que pede senha própria.
- Instaladores de toolchains não devem editar arquivos do shell (`--no-modify-path`, `UV_NO_MODIFY_PATH=1`, `--skip-shell`): o `.zshrc` do repositório é a fonte do PATH.
- Quando o instalador oficial não tem opção para isso (ex: `pnpm setup` e `agy install`, que sempre editam o perfil), rode-o com um `HOME` descartável (`env HOME="$(mktemp -d)"`) e aponte o binário para o destino real (`PNPM_HOME`, `--dir`). Teste num `HOME` isolado que o `.zshrc` continua idêntico.

## 6. Como Adicionar Novos Passos
Quando uma IA for solicitada a "adicionar um novo passo na automação", ela deve:
1. Criar o novo script em `scripts/NN-nome.sh` (o número define a posição no menu e no `--all`; nome com no máximo 24 caracteres, incluindo `.sh`).
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
3. Escrever a lógica idempotente, com o ramo `dnf` seguindo `06-fedora.md`.
4. Dar permissão de execução (`chmod +x`), para o git registrar o modo `100755`.
5. Não é preciso editar o `app.sh`: o menu descobre o módulo pelo cabeçalho.
6. Atualizar a tabela de módulos em `02-architecture.md` e no `README.md`. Se o módulo ler uma nova chave do `.env`, adicioná-la ao `.env.example`.
7. Rodar a validação da seção 7.

## 7. Validação Obrigatória Antes de Entregar
NUNCA execute os módulos reais no sistema do usuário para testar: eles instalam pacotes, alteram `/etc` e o bootloader. Valide assim:
1. **Verificações estáticas**: `bash tools/check.sh` (deve terminar em "All checks passed"). Cobre sintaxe (`bash -n`, `zsh -n`), shellcheck (local ou via podman), convenções dos módulos (cabeçalhos, limites de 24/44 caracteres, preâmbulo, permissão de execução), largura do menu, caminhos do `$HOME` e emojis.
2. **Comportamento interativo** (Ctrl+C, prompts): teste num pseudo-terminal real (ex: `pty.fork()` do Python). Processos em segundo plano de um shell não interativo herdam o SIGINT ignorado, o que invalida testes de Ctrl+C feitos com `&`.
3. **Pacotes dnf** (não exige root): `dnf repoquery --available <pacote>` para cada nome novo e `dnf install --assumeno <lista completa>` para a transação. Para repositórios ainda não configurados: `--repofrompath=<id>,<url> --repo=<id>`.
4. **Remoções** (não exige root): `dnf remove --assumeno <pacotes>` para ver o que mais seria removido.
5. **Flatpak**: `flatpak remote-info flathub <app-id>`.
6. **Módulos sem root** (01, 07, 08): execute com `HOME` e `XDG_CONFIG_HOME` apontando para um diretório temporário, e rode duas vezes para provar a idempotência.
7. **Módulo 11 (GNOME)**: nunca rode `dconf load` na sessão real do usuário para testar. Execute o módulo com `HOME` temporário, `DBUS_SESSION_BUS_ADDRESS` apontando para um socket inexistente e `sudo`/`dconf` falsos no `PATH` (que só registram as chamadas). Valide os `.ini` com `dconf load` real dentro de um container: `podman run --rm -v "$PWD/style/gnome:/mnt/gnome:ro,Z" registry.fedoraproject.org/fedora:44` com `dbus-daemon` e `dconf` instalados e `dbus-run-session`.
8. **Ajustes no `tools/check.sh`**: ao criar uma nova convenção verificável, acrescente a checagem lá. O mesmo script roda no CI (Ubuntu): não use `awk` para contar caracteres (o `mawk` do Ubuntu conta bytes) e mantenha o shellcheck na imagem fixa (0.11.0).
9. **Ramo apt**: valide num container `docker.io/library/ubuntu:24.04` com `apt-get install -s` (simulação) e, para repositórios de fornecedor, execute o próprio bloco do módulo dentro do container antes de simular.
10. **Harness de teste**: ao medir código de saída num pseudo-terminal, colha o processo com espera bloqueante; um `waitpid` com `WNOHANG` que ainda não terminou devolve status 0 e mascara falhas.

## 8. Configurações do GNOME
- Não edite `style/gnome/dconf/*.ini` nem `extensions.txt` à mão quando a mudança puder ser feita no GNOME e reexportada com `bash style/gnome/bin/export-gnome-settings.sh`.
- Ao incluir uma nova seção do dconf no exportador, confira o conteúdo: o dconf guarda estado da máquina e dados pessoais (histórico de pastas, contas, credenciais de rede como `org/gnome/nm-applet/eap`). Inclua por lista de seções permitidas, nunca o dump inteiro. Os filtros de segredos do exportador (`SECRET_KEY_RE`, `SECRET_VALUE_RE`, `EMAIL_RE`) valem para todas as seções; ao ampliá-los ou mudá-los, teste com um dump sintético contendo segredos falsos (um `dconf` falso no `PATH` que imprime o dump) e confirme que a exportação real não muda.
- Caminhos dentro do `$HOME` devem virar o marcador `@HOME@` (o exportador faz isso e falha se sobrar algum).
