# DiskDesk 3 — Explorador de disquetes para CC: Tweaked

Interface escura com destaque ciano, barra lateral de unidades, ícones, busca e rodapé simplificado: **D: unidades · A: menu · H: ajuda**. O menu A reúne todas as ações, e o botão direito mostra ações do arquivo. Inclui editor de textos, impressão, backup versionado, restauração e transferência wireless.

## Instalar ou atualizar

### Instalador em um arquivo (recomendado)

Transfira apenas **`instalar_diskdesk.lua`** para o computador do jogo ou para um disquete e execute:

```text
instalar_diskdesk
```

Se estiver no disquete, use o caminho dele, por exemplo `disk/instalar_diskdesk`. Confirme com **s**. O instalador funciona offline: os três módulos Lua já estão embutidos nele. Instala em `/diskdesk-app/`, cria o atalho `/diskdesk.lua`, verifica os arquivos gravados e oferece abrir o programa ao terminar.

Depois, execute **`/diskdesk`** de qualquer pasta (ou `diskdesk` na raiz).

Ao atualizar, a pasta antiga `/diskdesk-app` e o atalho anterior são guardados em `/diskdesk-backup-<identificador>/previous/`. Os arquivos novos são preparados antes de substituir a instalação; se a publicação falhar, tenta restaurar a versão anterior e informa a pasta de recuperação. O instalador não modifica `startup` nem arquivos dos disquetes. Se a energia acabar durante a instalação, consulte essa pasta para recuperação manual.

O instalador ainda precisa ser transferido para o jogo uma vez. Ele pode ser levado em um floppy; não depende de um endereço de download, Pastebin ou HTTP habilitado.

### Instalação manual

Copie **os três arquivos para a mesma pasta do computador do jogo**:

```text
diskdesk.lua
diskdesk_services.lua
diskdesk_arrays.lua
```

O pacote `DiskDesk-3.zip` contém o instalador, os três módulos e este guia. Extraia no computador real antes de transferir para o Minecraft. Quem instala manualmente deve copiar ou atualizar os três módulos juntos; é mais simples executar o instalador atualizado.

Execute no CraftOS:

```text
diskdesk
```

Recomendado: **Advanced Computer** para as cores. Tela mínima 30×12; barra lateral a partir de 45 colunas. Não precisa de outros mods nem bibliotecas extras no jogo. Os scripts Python são testes para o computador real e não fazem parte da instalação.

## Interface e controles

Clique seleciona; duplo clique abre. Botão direito mostra ações do arquivo. O botão **A: menu** no rodapé dá acesso às funções sem precisar memorizar atalhos. O menu A está organizado por categorias e os menus possuem borda ciano. As janelas aceitam clique, setas e Enter; **F1** ou o botão **Voltar** fecha a janela sem encerrar o programa. Esc pode fechar a tela do computador no próprio Minecraft, por isso não é necessário no DiskDesk. Confirmações também aceitam **s** ou **n**.

| Tecla | Ação |
|---|---|
| A | Abrir o menu de ações |
| D | Escolher computador ou disquete |
| Setas / roda | Selecionar arquivo |
| Enter / Backspace | Abrir / voltar uma pasta |
| N / T / E | Nova pasta / novo texto / editar |
| C / M / V | Copiar / marcar para mover / colar no destino |
| R / X ou Delete | Renomear / excluir com confirmação |
| F / F1 | Buscar por nome nesta pasta / limpar busca |
| I | Configurar e consultar RAID 1 |
| L / J | Nomear / ejetar disquete |
| B / O | Criar backup / restaurar backup |
| Z / Y | Compactar em DDZ / extrair DDZ |
| S / G | Enviar / receber arquivo wireless |
| P | Imprimir texto ou continuar impressão |
| U | Ativar / silenciar sons |
| H / Q | Ajuda / sair |

O editor é o `edit` do CraftOS: Ctrl abre Salvar e Sair. Copiar/colar não sobrescreve arquivos existentes; pede outro nome. Para trocar arquivos entre disquetes com um único drive, use o computador como intermediário.

## Boot, armazenamento e ajuda

Ao iniciar o DiskDesk, uma tela de boot mostra o carregamento do explorador e a preparação dos dispositivos. É a abertura do programa, não uma alteração do boot do CraftOS nem do arquivo startup.

**USO** mostra a ocupação do disco atual. **D** abre o painel de armazenamento com porcentagem, barra, espaço livre e capacidade de cada unidade. As barras ficam vermelhas a partir de 90%. Quando a capacidade não está disponível, aparece `--`. Clique na unidade ou use setas e Enter para abri-la. **A → RAID e backup** reúne configuração, sincronização, backup e restauração.

H abre a **Central de ajuda**, dividida por assuntos, com texto ajustado à tela, rolagem, botões de tópicos e navegação por setas. F1 ou Voltar retorna ao explorador.

## Mover arquivos e pastas

Selecione o item, pressione **M**, entre na pasta de destino e use **V**. O item é copiado para um destino temporário e verificado antes de remover a origem, inclusive entre computador e disquetes. Pastas vazias e arquivos binários são preservados. O nome do destino não é sobrescrito: se existir, escolha outro.

Se faltar espaço ou houver falha, a origem fica preservada enquanto a cópia não foi publicada. Pode sobrar um `.partial`. Se a remoção da origem falhar após a publicação, confira os dois locais: a cópia verificada já está no destino. Mantenha os discos inseridos durante a operação.

## RAID e espelhamento automático por arquivos

Use **A → RAID e backup → Espelhamento automático RAID 1** ou **I**. Escolha o modo, o disco principal e os destinos. Na seleção múltipla, marque os discos com clique ou Enter e escolha **Confirmar**:

- **RAID 1 na raiz:** copia toda a estrutura diretamente para o outro floppy, incluindo arquivos soltos, pastas e histórico de backup. Não cria a pasta `RAID1`.
- **RAID 1 em pasta:** mantém o modo anterior, usando `RAID1/` no destino e preservando o que está fora dela. Não replica `.diskdesk-backups`.
- **Vários espelhos:** copia o principal na raiz de até oito floppies, cada um com sua própria cópia completa.

**Na raiz, arquivos extras do destino são removidos para igualá-lo ao principal.** O programa pede confirmação ao configurar. Alterações e exclusões também são replicadas depois: use backup versionado para guardar versões antigas. Configurações anteriores continuam no modo em pasta; desative e configure novamente para trocar o modo.

A configuração fica em `/.diskdesk-raid.cfg`, fora da instalação, e identifica os discos pelo ID. Trabalhe no principal: o DiskDesk bloqueia escrita nos espelhos pelas suas próprias operações. Outros programas não recebem essa proteção.

Sincroniza na abertura, depois de ações, ao detectar discos e aproximadamente a cada 10 segundos enquanto o explorador está ativo. Editor, ajuda e diálogos adiam a sincronização até o retorno. Mostra **Sincronizado**, **Pendente** ou **Degradado**. Se um espelho faltar, os outros ainda são atualizados; se faltar o principal, nada é copiado. Recoloque os mesmos discos para continuar.

A atualização prepara e verifica uma cópia completa antes da publicação. O destino precisa comportar **a cópia antiga e a nova ao mesmo tempo**, além das pastas e do registro de recuperação. Não soma a capacidade dos discos. Limite de 1024 itens e 32 níveis de pastas. Nomes começando com `.diskdesk-raid-` são reservados no modo raiz.

Os registros e diretórios `.diskdesk-raid-*` permitem recuperar uma publicação interrompida na próxima sincronização. Não os altere manualmente enquanto o conjunto estiver ativo. Se não houver registro válido para recuperar, o programa interrompe a operação e exige conferência manual. Mantenha os discos conectados durante a cópia.

Para recuperar após perder o principal, copie os dados de um espelho para outro disco: da raiz ou de `RAID1/`, conforme o modo. Não há promoção automática nem unidade virtual. Desativar o espelhamento mantém os dados já gravados. Os outros níveis de RAID estão no painel de conjuntos descrito a seguir.

## Conjuntos RAID 0, 1, 5, 6 e 1+0

**A → RAID e backup → Conjuntos RAID** guarda uma versão do arquivo ou pasta selecionado em blocos distribuídos pelos disquetes. É armazenamento próprio do DiskDesk: não monta uma unidade virtual do CraftOS, não altera a API `fs` e não sincroniza alterações posteriores automaticamente. Para guardar alterações, crie um novo conjunto; o anterior permanece disponível.

| Modo | Discos | Dados úteis aproximados* | Perdas recuperáveis |
|---|---|---|---|
| RAID 0 | 2 a 8 | N × capacidade do menor disco | Nenhuma; precisa de todos os membros |
| RAID 1 | 2 a 8 | Capacidade do menor disco | Até N−1 discos |
| RAID 5 | 3 a 8 | (N−1) × capacidade do menor disco | Qualquer disco isolado |
| RAID 6 | 4 a 8 | (N−2) × capacidade do menor disco | Quaisquer dois discos |
| RAID 1+0 | 4, 6 ou 8 | (N÷2) × capacidade do menor disco | Um por par; perder os dois de um par impede restaurar |

*Antes dos índices, arredondamento dos blocos e arquivos já presentes nos discos. O conteúdo original de cada conjunto continua limitado a 512 KiB e 1024 itens pela compactação DDZ.

1. Selecione um arquivo ou pasta no explorador.
2. Abra **Conjuntos RAID → Guardar item em novo conjunto** e escolha o nível.
3. Marque vários disquetes com Enter ou clique e use **Confirmar**. Use Disk Drives conectados ao computador; para mais drives, uma [rede de modems com fio](https://tweaked.cc/module/peripheral.html#referencing-peripherals) permite disponibilizar periféricos remotos.
4. Confira IDs, espaço por disco e, no RAID 1+0, a ordem dos pares. Confirme e aguarde a verificação.
5. Para recuperar, abra a pasta onde quer salvar e use **Abrir / recuperar conjunto → Restaurar nesta pasta**. Informe o nome de uma pasta nova.

Os originais e outros arquivos dos disquetes são preservados. Cada conjunto fica em `.diskdesk-arrays/<identificador>/`, com índice repetido e um arquivo de blocos por membro. Blocos têm 1024 bytes; RAID 5 usa paridade XOR rotativa, RAID 6 usa paridades P/Q em GF(256), e RAID 1+0 distribui os dados entre pares espelhados. A implementação matemática de P/Q segue os princípios descritos em [The mathematics of RAID-6](https://www.kernel.org/pub/linux/kernel/people/hpa/raid6.pdf). O formato em disco é próprio e não é compatível com arrays Linux.

**Ver discos / integridade** valida tamanho e checksum de cada membro. Um arquivo de blocos corrompido conta como um disco perdido. Havendo redundância suficiente, **Reconstruir disco perdido** grava o membro em um disquete substituto e verifica o resultado. O substituto precisa estar conectado e não pode conter esse mesmo conjunto. A identificação do novo membro fica nele; não depende da configuração do computador original.

Mantenha os discos conectados até terminar. A criação prepara todos os membros antes de publicar. Se houver interrupção, podem restar diretórios `.partial` ou um conjunto incompleto; versões anteriores e originais permanecem intactos. Um conjunto incompleto só pode ser restaurado se houver membros suficientes. Não edite manualmente os índices ou blocos, e mantenha backups independentes dos dados importantes.

## Compactar e extrair

Selecione um arquivo ou pasta e use **A → Compactar e extrair**, ou **Z** para compactar e **Y** para extrair. O formato próprio **`.ddz`** preserva nomes, estrutura, pastas vazias e dados binários. Pode compactar uma pasta e enviar o pacote por wireless.

Agora escreve **DDZ2**, com índice binário, números de tamanho variável e referências às pastas pai, evitando repetir os caminhos completos. Comprime índice e conteúdo juntos com LZW quando isso reduz o tamanho; caso contrário guarda essa estrutura binária sem LZW. Continua extraindo os pacotes DDZ1 antigos; versões antigas do DiskDesk não leem DDZ2.

Arquivos muito pequenos ainda podem aumentar porque o pacote guarda nomes, estrutura e checksum. Um teste com uma pasta `pessoal` e dois arquivos `a.txt`/`b.txt` de 8 e 9 bytes verifica que o pacote fica abaixo de 80 bytes, em vez de centenas. O tamanho exato depende dos nomes e do conteúdo. A barra de status informa os tamanhos de entrada/saída e avisa quando o pacote inclui mais bytes de índice do que economizou. Não é ZIP nem remove os originais.

A extração valida caminhos, tamanho e checksum antes de publicar em uma **pasta nova**, sem sobrescrever arquivos existentes. Limites: 512 KiB de conteúdo descompactado, 1024 entradas e cabeçalho de 128 KiB. Espaço adicional é necessário para o pacote ou a extração. Falhas podem deixar um arquivo ou pasta `.partial`.

## Backup com versões

É **backup versionado por arquivos, iniciado manualmente**, separado do espelhamento automático. Cada execução copia o estado atual do disco para uma versão nova e mantém as anteriores, permitindo recuperar arquivos apagados ou alterados depois.

1. Conecte **dois Disk Drives**, com um floppy em cada. Dê nomes como `Trabalho` e `Backup` com L.
2. Abra o disco `Trabalho` na barra lateral ou com D.
3. Use **A → RAID e backup → Criar backup** ou pressione B.
4. Escolha o disco `Backup`, confira os discos e confirme.
5. Aguarde a cópia e a verificação. Mantenha os dois disquetes inseridos.

Inclui **todo o disquete selecionado**, mesmo se estiver em uma subpasta ou usando busca. Preserva estrutura, pastas vazias e conteúdo binário. Cada arquivo copiado é relido e comparado por tamanho e checksum Adler-32. O histórico `.diskdesk-backups` não é incluído em novos backups.

As versões ficam no destino em:

```text
.diskdesk-backups/<ID-do-disco-original>/<identificador-da-versao>/
  manifest
  data/
```

Se faltar espaço, remova manualmente versões antigas que não precisa mais ou use outro disquete. Cada versão é uma cópia completa e precisa de espaço adicional para pastas e índice. Limite de 1024 itens e 32 níveis de pastas por backup.

Um backup só aparece em Restaurar depois de concluído. Falhas podem deixar uma pasta `.partial`, que não é tratada como backup válido. Versões anteriores não são alteradas. Remover ou trocar o disco interrompe a operação; o programa confere o ID e o ponto de montagem durante a cópia.

### Restaurar

Abra o disquete que contém os backups, use **A → RAID e backup → Restaurar backup**, escolha a versão e outro disquete como destino. O programa verifica os arquivos e os coloca em uma **nova pasta `Restaurado-...`**, sem substituir arquivos existentes. Depois você pode organizar os arquivos pelo explorador. Em caso de interrupção, uma pasta de restauração `.partial` pode permanecer.

## Transferir arquivos por wireless

Instale o DiskDesk 3 nos dois computadores e conecte um **Wireless Modem** ou **Ender Modem** em cada. Precisam estar ligados e dentro do alcance da conexão; o DiskDesk não instala repetidores.

1. **Destino:** abra a pasta onde quer salvar e use **A → Rede wireless → Receber**. A tela mostra o ID; também está no cabeçalho. Aguarda uma oferta por até 60 segundos, com F1 para cancelar.
2. **Origem:** selecione um arquivo e use **A → Rede wireless → Enviar**. Digite o ID do destino.
3. **Destino:** confira ID do remetente, nome e tamanho e aceite.
4. Aguarde a confirmação. O arquivo aparece na pasta escolhida após ser verificado.

Envia um arquivo por vez, inclusive binários, de até **1 MiB**, em blocos de 8 KiB. Pastas não são enviadas diretamente. Há confirmação dos blocos, tentativas de reenvio e checksum. A aceitação pode levar até cerca de 90 segundos; após iniciada, uma transferência sem progresso por 15 segundos é interrompida.

Se o nome existir, a cópia recebe um sufixo (`arquivo.txt-2`, por exemplo). O arquivo só sai do nome temporário `.partial` após a verificação. Não executa arquivos recebidos. Se faltar a confirmação final, confira o destino antes de reenviar: o arquivo pode já estar salvo.

Rednet não oferece criptografia nem autenticação dos IDs. A confirmação permite escolher ofertas, mas não prova a identidade do remetente. Use em redes de jogadores confiáveis. O checksum detecta erros acidentais; não é uma assinatura de segurança. [Documentação do Rednet](https://tweaked.cc/module/rednet.html).

## Impressora e sons

Conecte uma **Printer**, abasteça com papel e corante, selecione um texto e pressione P. O programa quebra linhas e divide em páginas. Se faltar material ou a saída estiver cheia, reabasteça e tente novamente; pode voltar ao explorador e continuar com P. O trabalho fica na memória: não reinicie nem imprima com outro programa enquanto houver trabalho pendente.

Conecte um **Speaker** para o acorde agudo ao inserir disco e grave ao retirar. Funciona nas perguntas, menus e editor. U silencia até fechar o programa. Sem Speaker, funciona sem áudio.

## Limites e testes

Visualização e impressão aceitam textos até 128 KiB; não interpretam imagens ou PDFs. A interface usa o terminal do computador, não monitor externo. Binários podem ser copiados, incluídos no backup e transferidos por wireless.

Testes com Lua e APIs simuladas incluem transferência com perda de pacotes, DDZ1/DDZ2, discos trocados durante gravação, publicação interrompida, reconstrução em substitutos e todas as duplas de discos ausentes em um RAID 6 de oito membros. RAID 1+0 também testa perdas dentro do mesmo par e entre pares distintos. A prévia vem das escritas reais no terminal simulado, com fonte aproximada. Ainda é necessário validar no Minecraft com periféricos reais.

Referências: [disquetes](https://tweaked.cc/module/disk.html), [arquivos](https://tweaked.cc/module/fs.html), [impressora](https://tweaked.cc/peripheral/printer.html), [Speaker](https://tweaked.cc/peripheral/speaker.html), [modem](https://tweaked.cc/peripheral/modem.html).
