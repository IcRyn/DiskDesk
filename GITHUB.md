# Colocar o DiskDesk no GitHub, pelo navegador

Não precisa instalar Git para começar.

1. Entre em sua conta no [GitHub](https://github.com/) ou [crie uma conta](https://github.com/signup).
2. Abra [New repository](https://github.com/new).
3. Use **diskdesk** como nome do repositório e escolha **Public**, para o computador do jogo baixar o instalador sem autenticação. Pode marcar **Add README** para iniciar o repositório.
4. Clique **Create repository**.
5. Extraia `DiskDesk-GitHub.zip` no seu computador real.
6. No repositório, use **Add file → Upload files**. Arraste os **arquivos extraídos**, mantendo `instalar_diskdesk.lua` diretamente na raiz, e não apenas o ZIP ou uma pasta externa.
7. Escreva uma mensagem como `Adicionar DiskDesk` e confirme **Commit changes**. Se o GitHub oferecer uma proposta de alteração/branch, conclua o pull request para colocar os arquivos na `main`.

Esses passos seguem os guias oficiais de [criação de repositório](https://docs.github.com/en/get-started/start-your-journey/creating-a-repository-for-your-project-on-github) e [upload de arquivos](https://docs.github.com/en/repositories/working-with-files/managing-files/adding-a-file-to-a-repository).

## Instalar no Minecraft

Se seu usuário for `SEU_USUARIO`, o repositório se chamar `diskdesk` e a branch for `main`:

```text
wget run https://raw.githubusercontent.com/SEU_USUARIO/diskdesk/main/instalar_diskdesk.lua
```

Troque `SEU_USUARIO` pelo seu nome real. Depois da instalação:

```text
/diskdesk
```

Se o arquivo estiver em outra pasta/branch, abra `instalar_diskdesk.lua` no GitHub e copie o endereço do botão **Raw**. O endereço da página `github.com/.../blob/...` não serve para o comando: ele entrega a página HTML, não o código Lua.

O download exige HTTP habilitado no CC: Tweaked. O instalador continua sendo um arquivo único e funciona offline depois de transferido.

## Atualizações

Se receber um instalador novo, envie o novo `instalar_diskdesk.lua` para o mesmo local e confirme a alteração. O comando de instalação continuará igual.

Se modificar os arquivos-fonte diretamente, gere o instalador de novo **no computador real**:

```text
python build_installer.py
```

Envie também o instalador regenerado. Alterar só `diskdesk.lua` no GitHub não muda o conteúdo que já está embutido no instalador.

## O que está no pacote do repositório

- Programa e serviços Lua.
- Instalador único, modelo do instalador e script que o gera.
- README, este guia e ideias futuras.
- Testes simulados e script da prévia.

O pacote não inclui seus mundos do Minecraft, disquetes ou configuração pessoal de RAID. Este guia não publica nada automaticamente: você escolhe o repositório e confirma o upload.
