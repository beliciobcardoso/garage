# Garage S3 com Docker Compose

Este projeto configura uma instância local e de nó único do **Garage S3**, um serviço de armazenamento de objetos leve, distribuído e compatível com a API S3.

## Estrutura do Projeto

- `docker-compose.yml`: Define o container Docker para o Garage v2.3.0.
- `garage.toml`: Arquivo de configuração contendo as portas e volumes.
- `.env`: Armazena com segurança as chaves internas `GARAGE_RPC_SECRET` e `GARAGE_ADMIN_TOKEN`.
- `init-s3.sh`: Script utilitário para automatizar a geração de chaves S3 e criação de buckets.

## Como Executar

### 1. Iniciar o Servidor

Para iniciar o Garage S3 em segundo plano (background):

```bash
docker compose up -d
```

### 2. Verificar o Status e Logs

Verifique se o container está rodando e saudável:

```bash
docker compose ps
```

Para inspecionar os logs do servidor em tempo real:

```bash
docker compose logs -f
```

---

## Inicialização Automática (Recomendado)

Você pode inicializar as credenciais e o bucket automaticamente executando o script utilitário:

```bash
./init-s3.sh [nome_da_chave] [nome_do_bucket]
```

Exemplo:
```bash
./init-s3.sh minha-chave meu-bucket
```

O script criará os recursos, exibirá as chaves de acesso no terminal e as salvará em um arquivo `.env.s3` para facilitar o uso na sua aplicação.

---

## Inicialização Manual (Alternativa)

Se preferir realizar o processo manualmente, execute os comandos a seguir com o container em execução:

### 1. Criar uma Chave de Acesso S3

Cria uma chave chamada `minha-chave` e exibe o **Key ID** (Access Key) e **Secret Key**:

```bash
docker compose exec garage garage key create minha-chave
```

*Guarde os valores gerados! Eles serão usados para configurar o seu cliente S3.*

### 2. Criar um Bucket

Cria o bucket chamado `meu-bucket`:

```bash
docker compose exec garage garage bucket create meu-bucket
```

### 3. Associar a Chave ao Bucket

Permita que a chave criada tenha acesso de leitura e escrita no bucket:

```bash
docker compose exec garage garage bucket allow meu-bucket --key minha-chave
```

---

## Como Conectar seu Cliente S3

Como o Garage S3 está rodando localmente, configure o seu cliente (ex: AWS CLI, MinIO Client `mc`, Rclone ou SDKs da sua aplicação) utilizando os seguintes parâmetros:

- **Endpoint URL**: `http://localhost:3900`
- **Region**: `sa-east-1`
- **Access Key**: *(O Key ID gerado no passo 1)*
- **Secret Key**: *(O Secret Key gerado no passo 1)*

> [!IMPORTANT]
> **Compatibilidade de Região**: A região configurada no cliente S3 (ou informada no `DEFAULT_REGION` do script `init-s3.sh`) **deve ser idêntica** ao valor de `s3_region` definido no arquivo `garage.toml`.
> Caso contrário, a assinatura das requisições falhará e o cliente receberá o erro `AuthorizationHeaderMalformed`.

### Exemplo com AWS CLI

Antes de executar comandos com o `aws-cli`, você precisa carregar as credenciais geradas. Você pode fazer isso de duas formas:

#### Opção A: Carregar temporariamente na sessão do terminal (Recomendado)
Execute o seguinte comando para exportar as credenciais do arquivo `.env.s3` na sessão atual do seu terminal:

```bash
export $(grep -v '^#' .env.s3 | xargs)
```

*(Se você executar o comando em outra pasta, forneça o caminho relativo ou absoluto para o arquivo `.env.s3`).*

#### Opção B: Configurar globalmente no AWS CLI
Você pode registrar as credenciais no AWS CLI executando o assistente de configuração:

```bash
aws configure
```
E inserindo os dados gerados (que constam no arquivo `.env.s3`):
- **AWS Access Key ID**: `GK...` (O Key ID gerado)
- **AWS Secret Access Key**: `...` (O Secret Key gerado)
- **Default region name**: `sa-east-1` (Deve ser igual ao configurado no `garage.toml`)
- **Default output format**: `json`

#### Testar a Conexão
Após carregar ou configurar as credenciais, liste os buckets no Garage local para verificar o funcionamento:

```bash
aws --endpoint-url http://localhost:3900 s3 ls
```
