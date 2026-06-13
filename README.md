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
- **Region**: `garage`
- **Access Key**: *(O Key ID gerado no passo 1)*
- **Secret Key**: *(O Secret Key gerado no passo 1)*

### Exemplo com AWS CLI

Para listar os buckets usando a AWS CLI:

```bash
aws --endpoint-url http://localhost:3900 s3 ls
```

*(Lembre-se de configurar as credenciais no seu ambiente antes de rodar o comando).*
