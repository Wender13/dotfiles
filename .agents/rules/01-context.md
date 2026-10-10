---
description: Contexto geral do projeto de Dotfiles e Setup
trigger: always_on
---

# Contexto do Projeto: Linux Desktop Automation

## Propósito
Este projeto é uma ferramenta de automação pessoal (Dotfiles e Setup de Ambiente) desenvolvida para configurar e padronizar máquinas Linux do zero. Ele transforma uma instalação limpa em um ambiente de desenvolvimento completo, instalando programas, configurando ferramentas e personalizando a interface gráfica.

## Público-Alvo e Filosofia
- Repositório pessoal: o único usuário é o próprio dono do repositório. Mesmo assim, nenhum nome de usuário, e-mail ou dado pessoal real pode aparecer nos arquivos (ver `05-security-and-git.md`).
- Três formas de uso: um menu interativo CLI (`./app.sh`, o usuário escolhe os módulos), um modo autônomo (`./app.sh --all`), que roda todos os módulos em sequência pedindo a senha do sudo uma única vez, e uma interface gráfica nativa do GNOME (`./app.sh --gui`) que faz o mesmo que o menu. Os dados pessoais do modo autônomo vêm do `.env`.
- Política de versões: o que já está instalado nunca é atualizado em silêncio. Quando há versão mais nova, o app mostra `atual -> nova`, avisa que versões novas podem quebrar recursos e segue a política escolhida: `ask` (pergunta uma vez por grupo; padrão do menu), `update` (atualiza) ou `keep` (mantém; padrão do `--all`). As flags `--ask`, `--update` e `--keep` têm prioridade sobre a chave `UPDATE_POLICY` do `.env`.
- Modo de configuração: `full` (padrão, aplica a configuração do repositório) ou `missing` (`--only-missing`, para máquinas já configuradas em parte): instala só o que falta, não remove nada, não atualiza (política `keep` por padrão) e mantém toda configuração que já existe. As flags `--full` e `--only-missing` têm prioridade sobre a chave `CONFIG_MODE` do `.env`.
- Os módulos rodam como usuário normal. O `sudo` é chamado apenas nas linhas que precisam dele; executar o projeto como root é bloqueado. Quando o usuário ainda não tem sudo (Debian instalado com senha de root), o módulo 00 usa o `su` uma vez para instalar o `sudo` e adicionar os grupos `sudo`/`wheel`, `adm` e `systemd-journal`.

## Distribuições Suportadas
- **Fedora 41+ (alvo principal)**: todo o ramo `dnf` usa sintaxe do dnf5 e é validado no Fedora. Regras específicas em `06-fedora.md`.
- **Debian 13 (trixie) ou mais novo, com GNOME**: suportado. Validado num container `debian:13` com apt real (fontes, chaves de fornecedores, `apt-get update`) e instalações simuladas. Regras específicas em `07-debian.md`.
- **Ubuntu e derivados (`apt`)**: suporte secundário. Validado por simulação (`apt-get -s`) num container Ubuntu 24.04, não numa instalação real.
- **Fedora Atomic (Silverblue, Kinoite...)**: não suportado; pacotes ali são aplicados com rpm-ostree, não dnf.
- **RHEL, CentOS, Rocky, Alma**: não suportados. O ramo `dnf` depende de repositórios exclusivos do Fedora (RPM Fusion, fedora-workstation-repositories), e o `detect_distro` aborta nessas distribuições.

## Desktop
- **GNOME (alvo)**: configurações, extensões, temas e apps do GNOME só são aplicados quando o GNOME é detectado (`is_gnome` do `lib.sh`): GNOME Shell instalado e sessão gráfica GNOME (`XDG_CURRENT_DESKTOP` contém `GNOME`: `GNOME` no Fedora, `ubuntu:GNOME` no Ubuntu). Sem sessão gráfica (TTY, SSH), basta o GNOME Shell instalado.
- **Outros desktops (KDE, Xfce, COSMIC...)**: as etapas do GNOME são puladas com um aviso, sem erro, e o restante (pacotes, Flatpaks, terminal, ambientes de dev, GRUB, Plymouth) roda normalmente. Pulados: os forks das extensões (01), a remoção do bloatware do GNOME e o GNOME Tweaks (04), o Extension Manager (05), os temas e o `sassc` (10) e os módulos 11 e 12 inteiros.

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

* Exceção (Antigravity CLI): instalador oficial (`https://antigravity.google/cli/install.sh`), binário `agy` em `~/.local/bin`, com atualização automática.

* Exceção (Antigravity IDE, decisão do usuário): o Google só publica o app para Linux como tarball (os repositórios apt/rpm pararam na 1.x). O módulo 13 o instala em `~/.local/share/antigravity-ide`, com o comando `antigravity-ide` e um atalho no menu. O tarball não se atualiza sozinho: a versão nova é lida na página oficial de download (`antigravity.google/download?os=linux`) e segue a política de versões. O "Antigravity 2.0" da mesma página não é instalado, por escolha do usuário.

* Claude Desktop: repositório apt oficial da Anthropic (nível 1), só para Debian 12+ e Ubuntu 22.04+ (módulo 13). No Fedora não há pacote oficial: o módulo avisa e não usa conversores da comunidade (decisão do usuário).

* Extensões do GNOME: usar o pacote do Fedora (`gnome-shell-extension-*`) quando existir, atualizado pelo dnf; as demais vêm do extensions.gnome.org, na versão compatível com o GNOME Shell instalado. Nunca de clones de repositório.

## Tecnologias Envolvidas
- Linguagem principal: `bash`
- Customização de Interface: GNOME (tema Orchis, ícones Tela Circle, cursores Vimix, extensões, configurações e atalhos via dconf, papel de parede e foto do usuário, GRUB, Plymouth) e possivelmente Cosmic no futuro.
- Terminal: `zsh` + `oh-my-zsh` + plugins + tema Spaceship.
