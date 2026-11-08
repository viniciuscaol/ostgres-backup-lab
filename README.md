# PostgreSQL Backup Lab

Laboratório de automação de backup e recuperação com **Bash, PostgreSQL 17 e Docker Compose**. Um arquivo gerado não basta: cada backup é restaurado em um cluster separado e seus dados são verificados antes de entrar na retenção.

Dados totalmente sintéticos: dois equipamentos de rede e três chamados de suporte. Não exige AWS, conta em nuvem ou servidor pago.

## O que demonstra

- `pg_dump` em formato custom, com compressão padrão do PostgreSQL.
- SHA-256 para detectar alterações no arquivo.
- `pg_restore` com transação única, interrupção em caso de erro e sem restaurar proprietários/permissões.
- Conferência de tabelas, valores, contagens, índice e uso das sequências restauradas.
- Publicação por renomeação de diretório, somente após restauração validada.
- Retenção dos últimos três backups válidos e bloqueio contra execuções simultâneas.
- Testes reais de recuperação e falhas no GitHub Actions.

## Executar

Pré-requisitos: Git e Docker com Compose v2. Os comandos abaixo usam um terminal Bash no Linux, macOS ou WSL.

```bash
git clone https://github.com/viniciuscaol/ostgres-backup-lab.git
cd ostgres-backup-lab
docker compose up -d --wait source-db restore-db
docker compose run --rm runner
```

Ao final, procure `RESTORE_OK` e `BACKUP_OK`. O nome do diretório aparece no log:

```text
RESTORE_OK database=verify_... devices=2 tickets=3
BACKUP_OK name=backup_... bytes=... duration_seconds=...
```

Listar backups e verificar novamente um deles:

```bash
docker compose run --rm runner bash -c 'ls -1 /backups/backup_*'
# Substitua o nome abaixo pelo diretório mostrado em BACKUP_OK.
docker compose run --rm runner bash scripts/verify.sh /backups/backup_NOME_DO_LOG
```

Alterar a retenção para dois backups:

```bash
docker compose run --rm -e KEEP_BACKUPS=2 runner
```

Cada backup contém `database.dump`, `database.sha256` e `VERIFIED` (data UTC e duração). Eles ficam no volume Docker `backups`, preservado ao executar `docker compose down`.

Exportar uma cópia do volume para um arquivo local, sem outro backup em execução:

```bash
docker compose run --rm -T runner tar -C /backups -cf - . > backups.tar
```

O arquivo exportado deve ficar fora do Git; o `.gitignore` já ignora arquivos `.tar` e `.dump`.

## Testar

```bash
docker compose run --rm runner bash scripts/integration.sh
```

Resultado esperado: `TESTS_OK`. O teste cria seu próprio diretório de backups, produz três cópias, confirma a retenção de duas e restaura uma delas novamente. Também testa concorrência, origem inacessível, dados divergentes, checksum inválido, arquivo inválido e tentativa de usar um destino de restauração indevido. Após falhas, confere a preservação dos backups e a limpeza dos bancos temporários. O teste altera temporariamente um chamado sintético e o devolve ao valor original; execute apenas neste laboratório.

O workflow executa esses testes com PostgreSQL real e verifica Bash, ShellCheck e Compose a cada PR e atualização da `main`. O workflow não publica dados nem faz deploy.

## Como funciona

O `runner` conecta-se à origem para executar o dump. Calcula o checksum e restaura o arquivo em um banco `verify_*` novo no serviço `restore-db`. A validação SQL compara os dados com o contrato fixo de `sql/verify.sql`. O banco temporário é removido após a verificação, inclusive quando ela falha. Só depois o diretório temporário é promovido e as cópias antigas são removidas.

Os dois servidores têm volumes e redes separados. Somente o runner participa das duas redes; nenhuma porta é publicada no computador. A restauração aceita exclusivamente `restore-db:5432`, cria um nome próprio e não aceita um banco de destino informado pelo usuário. As credenciais no Compose são públicas e exclusivas dos dados fictícios deste laboratório.

| Arquivo | Responsabilidade |
| --- | --- |
| `compose.yaml` | Origem, cluster de restauração e runner |
| `scripts/backup.sh` | Dump, checksum, validação, publicação e retenção |
| `scripts/verify.sh` | Restauração isolada, verificação SQL e limpeza |
| `scripts/integration.sh` | Cenários de sucesso e falha |
| `sql/seed.sql` | Equipamentos e chamados sintéticos |
| `sql/verify.sql` | Contrato de dados esperado |

## Escopo e limites

Este projeto verifica **o conjunto de dados fixo do laboratório**. Ele não compara automaticamente bancos arbitrários, não é uma ferramenta de backup de produção e não deve ser apontado para um ambiente real. Se mudar o seed, ajuste o contrato de validação e recrie os volumes do laboratório.

O dump cobre um banco, sem backup de roles globais, tablespaces, WAL ou recuperação para um instante específico (PITR). A restauração ignora proprietários e ACLs. O checksum detecta corrupção, mas não autentica a origem de um arquivo. Só restaure dumps confiáveis: o PostgreSQL executa o SQL contido neles.

Os backups no volume local não protegem contra perda do computador. Agendamento externo, armazenamento remoto, criptografia e monitoramento de falhas ficam como evoluções. A imagem é fixada na versão principal 17; atualizações corretivas podem mudar a imagem obtida.

Interromper e preservar os dados:

```bash
docker compose down
```

**Apagar todos os dados e backups do laboratório**, se quiser começar novamente:

```bash
docker compose down --volumes
```

## Referências

- [Documentação oficial: pg_dump 17](https://www.postgresql.org/docs/17/app-pgdump.html)
- [Documentação oficial: pg_restore 17](https://www.postgresql.org/docs/17/app-pgrestore.html)

Licença MIT, conforme `LICENSE`.
