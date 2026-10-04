---
description: Regras de segurança de dados e padrões estritos de Git e Commits
trigger: always_on
---

# Segurança, Git e Padrões de Commit

Este documento define regras inegociáveis sobre como lidar com dados sensíveis e como realizar commits neste repositório. Nenhuma IA tem permissão para contornar estas diretrizes.

## 1. Segurança e Privacidade (Secrets e Pessoal)
- **Zero Segredos e Dados Pessoais Hardcoded**: É absolutamente ESTRITO E PROIBIDO escrever ou salvar **e-mails, nomes de usuário (usernames), senhas**, chaves SSH, tokens de API (GitHub, Spotify, etc) ou qualquer informação pessoal identificável diretamente nos arquivos, scripts ou commits do repositório.
- **Abordagem para Dados Sensíveis**: Se um script necessitar de e-mail, username ou qualquer credencial para funcionar, você DEVE programá-lo para ler de um arquivo `.env` que esteja no `.gitignore` (via `load_env` do `lib.sh`) e, se o valor estiver ausente, solicitar a informação dinamicamente ao usuário em tempo de execução (usando `read -r -p`). Isso vale também para URLs que contenham o nome de usuário (ex: forks no GitHub usam `GITHUB_USER`).
- **Única exceção ao username**: o `LICENSE` (MIT) traz o username do GitHub como titular dos direitos, por decisão do usuário. Ele já é público na URL do repositório e no e-mail noreply dos commits. Nenhum outro arquivo deve conter o username.
- **Chaves do `.env`**: toda nova chave deve ser documentada no `.env.example` apenas com valores de exemplo (placeholders), nunca com dados reais. Chaves atuais: `GIT_USERNAME`, `GIT_EMAIL`, `GITHUB_USER`, `GRUB_THEME_ARGS`, `UPDATE_POLICY`, `WALLPAPER_IMAGE`, `AVATAR_IMAGE`.
- **Imagens pessoais**: papel de parede e foto do usuário nunca são versionados (fotos pessoais e imagens com direitos autorais num repositório público). O módulo 12 as recebe pelo `.env` ou pelo seletor de arquivos.
- **Configurações do GNOME (dconf)**: o dconf guarda credenciais e dados pessoais (ex: certificados de Wi-Fi corporativo em `org/gnome/nm-applet/eap`, histórico de pastas, contas). Configurações só entram no repositório pelo `style/gnome/bin/export-gnome-settings.sh`, que: (1) só exporta seções de uma lista permitida; (2) descarta chaves com nome de segredo (token, secret, password, api-key, appid, credential, oauth, cookie) quando o valor é texto; (3) descarta valores com formato de credencial (tokens do GitHub/GitLab/Slack, JWT, chaves privadas, `Authorization`/`Bearer`, `password=` e afins em comandos) e e-mails; (4) troca o caminho do `$HOME` por `@HOME@`; e (5) aborta se um valor suspeito ou o `$HOME` ainda chegar à saída. O que foi descartado é listado no fim, para ser configurado à mão. As heurísticas não são garantia: nunca commite um `dconf dump /` inteiro e revise o `git diff` de `style/gnome/` antes de commitar.
- **Proteções de execução**: o `--all` invalida as credenciais do sudo ao terminar (`sudo -k`); o módulo 11 só baixa extensões de caminhos `/download-extension/` do extensions.gnome.org; o módulo 01 valida o formato do `GITHUB_USER` antes de montar URLs (o tema GRUB desses repositórios é instalado com sudo). Não remova essas checagens.
- **Logs do `--all`**: ficam fora do repositório (`~/.local/state/dotfiles/logs`, pasta 700) e contêm a saída da execução, inclusive a identidade git e a chave pública SSH mostradas pelo 07. Nunca copie logs para o repositório (`*.log` está no `.gitignore`). O log nunca grava o que é digitado (a senha do sudo não aparece).
- **CI**: o workflow tem permissão apenas de leitura (`contents: read`) e as ações de terceiros são fixadas por hash de commit, não por tag.
- **Prevenção de Comandos Destrutivos**: Não sugira nem execute comandos de alto risco sem contexto (como `rm -rf` indiscriminado ou `chmod -R 777`). Todas as alterações de permissão e deleção de arquivos devem ser cirúrgicas e específicas. Remoções de pacotes exigem checagem de dependências reversas (ver `06-fedora.md`).

## 2. Padrões de Git e Commits
Antes de realizar qualquer commit, você DEVE rodar `git diff` e `git status` para garantir que nenhum dado sensível foi incluído acidentalmente. 

Todos os commits devem seguir este formato estrito:
1. **Idioma**: Inglês ESTRITO (English ONLY).
2. **Semântica (Conventional Commits)**: O título deve começar com o tipo da mudança:
   - `feat:` (nova funcionalidade/módulo)
   - `fix:` (correção de erro/bug)
   - `chore:` (manutenção, atualizações de dependência)
   - `refactor:` (mudança de código que não adiciona feature nem corrige bug)
   - `docs:` (mudanças apenas em documentação)
3. **Estrutura do Commit**:
   - **Título**: Um resumo conciso do que foi alterado.
   - **Corpo (Body)**: Um parágrafo ou lista detalhada explicando o *porquê* da alteração e *quais* mudanças técnicas foram feitas.
   - **Proibido**: NÃO inclua tags de "Co-authored-by", assinatura de IA ou afins no rodapé. Apenas o título e o corpo.
4. **Commits Atômicos**: Não agrupe mudanças não relacionadas. Cada commit deve representar uma única unidade lógica de mudança.

### Exemplo do Padrão Esperado:
```text
feat: add postman installation to flatpak script

Migrated the Postman installation from the snap script to the flatpak script
because snap is not supported natively on Fedora. This ensures cross-distro 
compatibility when setting up developer tools.
```
