# Implantação do Garage S3 no Coolify

Este guia orienta o processo de implantação da sua instância do **Garage S3** no **Coolify**, uma alternativa open-source e auto-hospedada a plataformas de nuvem como Heroku ou Vercel.

---

## Pré-requisitos

1. Uma instância do Coolify instalada e operacional.
2. Apontamento de DNS (tipo `A` ou `CNAME`) apontando seus subdomínios (ex: `s3.seudominio.com`, `web.seudominio.com`, `admin.seudominio.com`) para o IP do servidor onde o Coolify está rodando.

---

## Passo a Passo para Implantação

### Passo 1: Criar um Novo Recurso no Coolify
1. Acesse o painel do Coolify.
2. Selecione o seu **Projeto** (Project) e o seu **Ambiente** (Environment - ex: Production).
3. Clique em **+ New** ou **New Resource** (Novo Recurso).
4. Selecione a opção **Docker Compose**.

### Passo 2: Definir o Docker Compose
Cole a estrutura do arquivo `docker-compose.yml` ajustada para o ambiente do Coolify:

```yaml
services:
  garage:
    image: dxflrs/garage:v2.3.0
    restart: unless-stopped
    volumes:
      - ./garage.toml:/etc/garage.toml:ro
      - garage-meta:/var/lib/garage/meta
      - garage-data:/var/lib/garage/data
      - garage-snapshots:/var/lib/garage/snapshots
    environment:
      - RUST_LOG=info
      - GARAGE_RPC_SECRET=${GARAGE_RPC_SECRET}
      - GARAGE_ADMIN_TOKEN=${GARAGE_ADMIN_TOKEN}
```

> [!NOTE]
> No Coolify, você não precisa expor as portas fisicamente (como `"3900:3900"`) se for utilizar os domínios reversos. O Coolify (através do Traefik ou Caddy) fará o roteamento de rede interno diretamente para os subdomínios HTTPS.

### Passo 3: Configurar os Domínios (Reverse Proxy)
Na aba **General** do recurso recém-criado no Coolify:
1. Localize o campo **Domains** (Domínios).
2. O Coolify permite mapear múltiplos domínios mapeando-os para diferentes portas internas usando a vírgula (`,`).
3. Adicione os subdomínios no seguinte formato:

```
https://s3.seudominio.com:3900, https://web.seudominio.com:3902, https://admin.seudominio.com:3903
```

> [!IMPORTANT]
> O Coolify gerará certificados SSL automáticos da Let's Encrypt para todos os domínios configurados com `https://`.

> [!CAUTION]
> **Segurança da API de Administração**: Mapear `https://admin.seudominio.com:3903` expõe a porta de administração do Garage à internet. Embora ela esteja protegida pelo `GARAGE_ADMIN_TOKEN`, a recomendação de segurança padrão é **não expô-la publicamente**. Prefira gerenciar o cluster usando a aba **Terminal** interna do painel do Coolify ou através de uma rede privada/VPN (ex: WireGuard).

### Passo 4: Configurar as Variáveis de Ambiente
Na aba **Environment Variables** (Variáveis de Ambiente) no Coolify, adicione os valores confidenciais copiados do seu arquivo `.env`:

- `GARAGE_RPC_SECRET`: *(Copie o valor gerado de 32 bytes em hex)*
- `GARAGE_ADMIN_TOKEN`: *(Copie o valor gerado de 32 bytes em hex)*

### Passo 5: Criar o arquivo `garage.toml`
Para mapear o arquivo de configuração `./garage.toml` no Coolify:
1. Vá para a aba **Storage** (Armazenamento) do recurso no Coolify.
2. Na seção de arquivos montados (ou volumes de arquivo), adicione uma nova entrada para criar o arquivo `garage.toml`:
   - **File Path on Host / Source**: `./garage.toml` (ou selecione a opção de arquivo de configuração se disponível)
   - **Path inside Container**: `/etc/garage.toml`
3. Cole o conteúdo de configuração do seu `garage.toml` (sem as chaves, pois elas serão injetadas pelo ambiente):

```toml
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
metadata_snapshots_dir = "/var/lib/garage/snapshots"
metadata_auto_snapshot_interval = "6h"
db_engine = "sqlite"
replication_factor = 1

rpc_bind_addr = "[::]:3901"

[s3_api]
s3_region = "sa-east-1"
api_bind_addr = "[::]:3900"
root_domain = "localhost"

[s3_web]
bind_addr = "[::]:3902"
root_domain = ".web.garage"

[admin]
api_bind_addr = "[::]:3903"
```

Clique em **Save** (Salvar).

### Passo 6: Implantar (Deploy)
Clique em **Deploy** no canto superior direito para iniciar a construção e execução do container.

---

## Inicialização do Cluster no Coolify

Depois que o container estiver rodando (estado `Running` verde):

1. Vá para a aba **Terminal** do container no Coolify.
2. Execute o comando para obter o ID do nó:
   ```bash
   /garage status
   ```
3. Copie o ID do nó exibido nos logs (ex: `cd4a8eee2e411394`).
4. Aloque o nó no layout do cluster informando a capacidade física (ex: `10G` para 10 Gigabytes):
   ```bash
   /garage layout assign <ID_DO_NO> -z local -c 10G
   ```
5. Veja a prévia do layout configurado:
   ```bash
   /garage layout show
   ```
6. Aplique a versão do layout:
   ```bash
   /garage layout apply --version 1
   ```

### Criando sua Chave S3 e seu Bucket

Uma vez que o cluster está configurado e saudável no Coolify, você tem duas opções para gerar suas credenciais e buckets:

#### Opção A: Execução Automática e Independente (Recomendado)
Você pode usar o script `init-s3-coolify.sh` diretamente no servidor (VPS) onde o Coolify está rodando. Este script **não depende** do diretório do docker-compose e pode ser executado em qualquer pasta (por exemplo, na pasta do código-fonte da sua aplicação cliente). Ele detectará o container ativo do Garage, gerará as credenciais, criará o bucket e salvará tudo localmente em um arquivo `.env.s3`.

1. Copie o script `init-s3-coolify.sh` para a pasta de sua preferência no servidor.
2. Dê permissão de execução (se necessário):
   ```bash
   chmod +x init-s3-coolify.sh
   ```
3. Descubra o nome do seu container do Garage rodando no Coolify:
   ```bash
   docker ps --filter "status=running" --filter "name=garage" --format "{{.Names}}" | head -n 1
   ```
4. Execute o script passando o nome da chave, do bucket e o nome do container obtido:
   ```bash
   ./init-s3-coolify.sh minha-chave meu-bucket nome-do-container-no-coolify
   ```
   *(Nota: O script tenta autodetectar o nome do container do Garage caso você não o especifique).*

#### Opção B: Criação Manual
Ainda na aba **Terminal** do container no Coolify:

1. Gere uma chave API S3:
   ```bash
   /garage key create minha-chave
   ```
   *Guarde a `Access Key` e a `Secret Key` retornadas no terminal.*
2. Crie o bucket:
   ```bash
   /garage bucket create meu-bucket
   ```
3. Permita que a chave criada acesse o bucket com permissões completas (incluindo owner):
   ```bash
   /garage bucket allow meu-bucket --key minha-chave --read --write --owner
   ```

---

Pronto! Sua aplicação poderá se conectar ao Garage S3 em produção usando a URL pública configurada (ex: `https://s3.seudominio.com`), fornecendo a chave e o bucket correspondentes.

