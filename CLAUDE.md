# Instruções do Projeto para Agentes de IA

A fonte de verdade das regras é a pasta `.agents/rules/` (formato do Antigravity). Este arquivo resume as regras inegociáveis e importa as detalhadas no fim. `.cursorrules` e `.github/copilot-instructions.md` repetem o mesmo resumo para outras ferramentas: qualquer mudança aqui deve ser replicada neles.

## Regras Essenciais

1. **Idioma**: Converse e escreva documentação em Português. Mensagens de commit são em Inglês.

2. **Arquitetura**: O `app.sh` (menu e `--all`) e a interface gráfica (`gui/`, aberta por `./app.sh --gui`) apenas listam os módulos e delegam. Toda automação é um módulo em `scripts/NN-nome.sh` com os cabeçalhos `# MENU_DESC:` (máximo 44 caracteres) e `# CATEGORY:`. O menu descobre os módulos sozinho, então não é preciso editar o `app.sh`.

3. **Fail-Fast**: Todo módulo começa com `set -euo pipefail`, importa `scripts/lib.sh` e chama `detect_distro`. É proibido usar `|| true` para esconder erros e encadear comandos críticos com `&&`.

4. **Idempotência**: Rodar um módulo várias vezes não pode quebrar nem duplicar nada. Cheque antes de instalar, clonar, baixar, anexar linhas ou fazer backup. O que já está instalado nunca é atualizado em silêncio: use as funções da política de versões do `lib.sh` (`install_packages`, `install_flatpaks`, `offer_git_updates`, `confirm_updates`), que respeitam `--ask`/`--update`/`--keep`. No modo completar (`--only-missing`), nada é removido nem sobrescrito: toda etapa que remove, sobrescreve ou muda um ajuste existente verifica `only_missing` (`.agents/rules/03-standards.md`, seção 2.2).

5. **Fedora Primeiro**: O alvo principal é o Fedora 41+ com dnf5. Nunca use sintaxe do dnf4 e valide todo nome de pacote antes de usá-lo (`.agents/rules/06-fedora.md`). O Debian 13+ com GNOME também é suportado e validado em container (`.agents/rules/07-debian.md`); o Ubuntu é secundário e a família RHEL não é suportada. O desktop alvo é o GNOME: tudo que é específico dele (configurações, extensões, temas, apps do GNOME) passa por `require_gnome` (módulo inteiro) ou `gnome_only` (etapa) do `lib.sh`, e em outros desktops é pulado com aviso, nunca com erro.

6. **Documentação Arquitetural Profunda**: Os arquivos em `.agents/rules/` trazem o contexto detalhado de arquitetura e padrões (eles servem tanto para o Antigravity quanto para você) e são importados abaixo.

7. **Backlog e Modificações Maiores**: O arquivo `.agents/rules/04-backlog.md` contém pendências. Você é ESTRITAMENTE PROIBIDO de implementar itens do backlog unilateralmente. Sempre proponha, converse com o usuário e aguarde o consenso dele antes de modificar o código e limpar o backlog.

8. **Sem Emojis**: É estritamente proibido o uso de emojis na documentação, nos comentários ou em qualquer arquivo de texto dentro da pasta de agentes ou no código. Mantenha um tom profissional e limpo.

9. **Segurança e Git**: Nunca faça hardcode de senhas, chaves, e-mails ou nomes de usuário (usernames); dados pessoais vêm do `.env`. Configurações do GNOME entram no repositório apenas pelo `style/gnome/bin/export-gnome-settings.sh`, que filtra dados pessoais. Commits DEVEM ser em Inglês, usar Conventional Commits (feat, fix etc.), ter título resumido, corpo detalhado e não devem conter 'Co-authored-by'. Leia `.agents/rules/05-security-and-git.md` para o padrão exato.

10. **Validação**: Antes de entregar mudanças em scripts, rode `bash tools/check.sh` e as demais verificações da seção "Validação Obrigatória" de `.agents/rules/03-standards.md`. Nunca execute os módulos reais no sistema do usuário para testar.

## Regras Detalhadas (importadas automaticamente pelo Claude Code)

@.agents/rules/01-context.md
@.agents/rules/02-architecture.md
@.agents/rules/03-standards.md
@.agents/rules/04-backlog.md
@.agents/rules/05-security-and-git.md
@.agents/rules/06-fedora.md
@.agents/rules/07-debian.md
