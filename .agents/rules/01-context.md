---
description: Contexto geral do projeto de Dotfiles e Setup
trigger: always_on
---

# Contexto do Projeto: Linux Desktop Automation

## Propósito
Este projeto é uma ferramenta de automação pessoal (Dotfiles e Setup de Ambiente) desenvolvida para configurar e padronizar máquinas Linux do zero. Ele transforma uma instalação limpa em um ambiente de desenvolvimento completo, instalando programas, configurando ferramentas e personalizando a interface gráfica.

## Público-Alvo e Filosofia
- Repositório pessoal: o único usuário é o próprio dono do repositório. Mesmo assim, nenhum nome de usuário, e-mail ou dado pessoal real pode aparecer nos arquivos (ver `05-security-and-git.md`).
- Dupla funcionalidade: um menu interativo CLI (`./app.sh`, o usuário escolhe os módulos) e um modo autônomo (`./app.sh --all`), que roda todos os módulos em sequência pedindo a senha do sudo uma única vez. Os dados pessoais do modo autônomo vêm do `.env`.
- Os módulos rodam como usuário normal. O `sudo` é chamado apenas nas linhas que precisam dele; executar o projeto como root é bloqueado.

## Distribuições Suportadas
- **Fedora 41+ (alvo principal)**: todo o ramo `dnf` usa sintaxe do dnf5 e é validado no Fedora. Regras específicas em `06-fedora.md`.
- **Debian/Ubuntu e derivados (`apt`)**: suporte secundário. Validado por simulação (`apt-get -s`) num container Ubuntu 24.04, não numa instalação real.
- **Fedora Atomic (Silverblue, Kinoite...)**: não suportado; pacotes ali são aplicados com rpm-ostree, não dnf.
- **RHEL, CentOS, Rocky, Alma**: não suportados. O ramo `dnf` depende de repositórios exclusivos do Fedora (RPM Fusion, fedora-workstation-repositories), e o `detect_distro` aborta nessas distribuições.

## Hierarquia e Prioridade de Pacotes
A instalação de software obedece rigorosamente à seguinte ordem de preferência:
1. **Repositórios Nativos (`apt` / `dnf`)**, incluindo repositórios oficiais de fornecedores com chave GPG (VSCode, Google Chrome, Docker, MongoDB), porque atualizam junto com o sistema.
2. **Flatpak** (Flathub, instalação de sistema)
3. **Arquivos soltos (`tar`, `zip`, scripts de extração)**
4. **AppImage** (Último recurso)

* Aversão ao Snap: O gerenciador `snap` deve ser ativamente **evitado** em todas as distribuições (incluindo Ubuntu/Debian). Se um pacote estiver no formato Snap, deve-se priorizar sua versão em Flatpak ou repositório nativo.

* Exceção à regra (Autoupdate): Aplicativos que distribuem pacotes `.deb` ou `.rpm` de forma isolada (onde o usuário teria que baixar manualmente o pacote de novo para atualizar, como DBeaver, Discord, MongoDB Compass etc.) DEVEM ser instalados via **Flatpak** para garantir a atualização automática. Antes, verifique se o fornecedor oferece um repositório oficial (nível 1).

* Exceção (pacote avulso exigido pelo fornecedor): o Docker Desktop só é distribuído como `.rpm`/`.deb` avulso. Ele é baixado da URL "latest" do fornecedor e instalado apenas se ainda não estiver instalado.

* Exceção (toolchains de linguagem): o `fnm` (Node.js) usa o instalador oficial no `$HOME`. No ramo apt, `rustup` e `uv` também usam os instaladores oficiais. Todos rodam sem alterar arquivos do shell, pois o `.zshrc` do repositório já configura o PATH. No Fedora, `rustup`, `uv` e `eza` vêm do dnf (nível 1).

* Exceção (pnpm, decisão do usuário): instalador oficial autônomo em `~/.local/share/pnpm`, independente da versão do Node. O pacote `pnpm` do Fedora foi descartado porque puxa um Node.js de sistema ao lado do fnm.

* Exceção (Claude Code, decisão do usuário): instalado pelo método que o site oficial recomenda, o instalador nativo (`curl -fsSL https://claude.ai/install.sh | bash`, no módulo 09). Ele fica em `~/.local/bin`, se atualiza sozinho em segundo plano e não deve ser trocado pelo repositório dnf/apt nem pelo npm.

* Exceção (Antigravity CLI): instalador oficial (`https://antigravity.google/cli/install.sh`), binário `agy` em `~/.local/bin`, com atualização automática. O aplicativo Desktop ainda não é automatizado (ver backlog).

* Extensões do GNOME: usar o pacote do Fedora (`gnome-shell-extension-*`) quando existir, atualizado pelo dnf; as demais vêm do extensions.gnome.org, na versão compatível com o GNOME Shell instalado. Nunca de clones de repositório.

## Tecnologias Envolvidas
- Linguagem principal: `bash`
- Customização de Interface: GNOME (tema Orchis, ícones Tela Circle, cursores Vimix, extensões, configurações e atalhos via dconf, GRUB, Plymouth) e possivelmente Cosmic no futuro.
- Terminal: `zsh` + `oh-my-zsh` + plugins + tema Spaceship.
