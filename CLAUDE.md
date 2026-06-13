# CLAUDE.md — AI Development & S3 Connection Instructions

Este documento fornece instruções técnicas para assistentes de IA (Claude, GPT, Cursor, Copilot) entenderem a arquitetura do projeto Garage S3 local, os comandos do ecossistema e as regras cruciais de integração para conectar qualquer aplicação cliente.

---

## 1. Project Overview & Commands

Este é um projeto local e de nó único do **Garage S3** rodando em Docker Compose. Ele escuta na porta `3900` para a API S3 e na porta `3903` para administração.

### Regra Obrigatória: SEMPRE use `rtk` prefix

**Todo comando bash deve ser prefixado com `rtk`.** O RTK é seguro para qualquer comando — se não tem filtro específico, ele faz pass-through. Sem exceção.

### Comandos de Infraestrutura (Execute prefixando com `rtk`):
*   **Iniciar infraestrutura:** `docker compose up -d`
*   **Parar infraestrutura:** `docker compose down`
*   **Parar e limpar volumes:** `docker compose down -v`
*   **Ver status dos containers:** `docker compose ps`
*   **Visualizar logs do Garage:** `docker compose logs -f`
*   **Inicializar S3 localmente (via docker-compose.yml):** `./init-s3.sh <nome-da-chave> <nome-do-bucket>`
    *   *Nota:* Executado no mesmo diretório do arquivo `docker-compose.yml`.
*   **Inicializar S3 de forma independente (Produção/Coolify):** `./init-s3-coolify.sh <nome-da-chave> <nome-do-bucket> [nome-do-container]`
    *   *Nota:* Pode ser executado de qualquer diretório da máquina/VPS, autodetecta o container Docker e gera o arquivo `.env.s3` localmente.


---

## 2. Parâmetros de Conexão S3 (S3 Connection Specs)

Qualquer aplicação integrada a este Garage deve usar os seguintes parâmetros:

*   **Endpoint URL:** `http://localhost:3900` *(Protocolo HTTP, sem SSL/TLS localmente)*
*   **Region:** `sa-east-1` *(Deve bater exatamente com `s3_region` no `garage.toml`)*
*   **Access Key ID:** Encontrado no arquivo gerado `.env.s3` (Ex: `GK...`)
*   **Secret Access Key:** Encontrado no arquivo gerado `.env.s3`

---

## 3. Diretrizes Cruciais para Geração de Código S3 (AI Coding Rules)

> [!IMPORTANT]
> **REGRAS MANDATÓRIAS PARA CODIFICAR INTEGRAÇÃO S3:**
>
> 1.  **Forçar Path-Style (Endereçamento por Caminho):**
>     Por padrão, os SDKs da AWS tentam usar o estilo de host virtual (ex: `http://meu-bucket.localhost:3900/`). O Garage local **não** suporta isso sem configurações adicionais de DNS.
>     **Você deve obrigatoriamente habilitar o Path-Style** no cliente S3 do seu SDK (ex: `forcePathStyle: true` em JS/TS, `UsePathStyle: true` em Go, `addressing_style: 'path'` no Boto3 do Python).
> 
> 2.  **Sincronização de Região (`sa-east-1`):**
>     A região passada ao SDK cliente **deve ser idêntica** à região configurada no servidor (`sa-east-1`). Se houver discrepância (ex: usar `us-east-1`), o Garage retornará erro `AuthorizationHeaderMalformed (400)`.
> 
> 3.  **Carregamento seguro de credenciais:**
>     Nunca chumbe chaves de acesso diretamente no código. Oriente o desenvolvedor a carregar o arquivo `.env.s3` ou mapeá-lo como variáveis de ambiente na aplicação.

---

## 4. Exemplos Práticos de Integração (Code Snippets)

### Node.js / TypeScript (AWS SDK v3 `@aws-sdk/client-s3`)
```typescript
import { S3Client, PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";

// Configuração do Cliente compatível com Garage S3
const s3Client = new S3Client({
  endpoint: process.env.AWS_ENDPOINT_URL || "http://localhost:3900",
  region: process.env.AWS_DEFAULT_REGION || "sa-east-1",
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID!,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY!,
  },
  forcePathStyle: true, // MANDATÓRIO: Força o path-style
});

// Exemplo de Upload
export async function uploadToGarage(bucket: string, key: string, fileBuffer: Buffer, contentType: string) {
  const command = new PutObjectCommand({
    Bucket: bucket,
    Key: key,
    Body: fileBuffer,
    ContentType: contentType,
  });
  return await s3Client.send(command);
}
```

### Python (Boto3)
```python
import os
import boto3
from botocore.config import Config

# Configuração do Cliente compatível com Garage S3
s3_client = boto3.client(
    's3',
    endpoint_url=os.getenv('AWS_ENDPOINT_URL', 'http://localhost:3900'),
    region_name=os.getenv('AWS_DEFAULT_REGION', 'sa-east-1'),
    aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
    aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY'),
    config=Config(s3={'addressing_style': 'path'}) # MANDATÓRIO: Força path-style
)

def upload_file(bucket_name, file_key, data):
    return s3_client.put_object(Bucket=bucket_name, Key=file_key, Body=data)
```

### Go (AWS SDK v2)
```go
package main

import (
	"context"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

func GetGarageClient(ctx context.Context, keyId, secretKey string) (*s3.Client, error) {
	// Endpoint resolver customizado para apontar para o Garage local
	resolver := aws.EndpointResolverWithOptionsFunc(func(service, region string, options ...interface{}) (aws.Endpoint, error) {
		return aws.Endpoint{
			URL:           "http://localhost:3900",
			SigningRegion: "sa-east-1",
		}, nil
	})

	cfg, err := config.LoadDefaultConfig(ctx,
		config.WithEndpointResolverWithOptions(resolver),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(
			keyId,
			secretKey,
			"",
		)),
	)
	if err != nil {
		return nil, err
	}

	return s3.NewFromConfig(cfg, func(o *s3.Options) {
		o.UsePathStyle = true // MANDATÓRIO: Força path-style
	}), nil
}
```

### PHP (AWS SDK for PHP)
```php
use Aws\S3\S3Client;

$s3Client = new S3Client([
    'version'                 => 'latest',
    'region'                  => 'sa-east-1',
    'endpoint'                => 'http://localhost:3900',
    'use_path_style_endpoint' => true, // MANDATÓRIO: Força path-style
    'credentials'             => [
        'key'    => getenv('AWS_ACCESS_KEY_ID'),
        'secret' => getenv('AWS_SECRET_ACCESS_KEY'),
    ],
]);
```

---

## 5. Configuração de CORS no Bucket (CORS Setup)

Se a sua aplicação web fizer uploads diretos a partir do navegador para o Garage S3 (ex: via Presigned URLs), você enfrentará problemas de CORS. O Garage não possui configuração de CORS global no `garage.toml`, mas suporta a API de CORS S3 padrão por bucket.

Você pode solucionar isso de três formas:

### Opção 1: Automática (via script de bootstrap)
Os scripts `./init-s3.sh` e `./init-s3-coolify.sh` tentarão automaticamente aplicar uma regra de CORS aberta (`*`) no bucket recém-criado caso o `aws-cli` esteja instalado no host/servidor, rodando internamente com as chaves temporárias.

### Opção 2: Via Script Node.js no Projeto Cliente
Você pode copiar o script `configure-cors.js` para a pasta do seu projeto cliente e executá-lo (requer `@aws-sdk/client-s3` instalado):
```bash
# Executar a partir da pasta que contém o seu arquivo .env.s3
node configure-cors.js
```

### Opção 3: Injeção no Proxy Reverso (Coolify / Traefik / Caddy)
Você pode configurar o proxy reverso do Coolify para injetar cabeçalhos de CORS nas requisições. 
No caso do **Traefik** no Coolify, adicione as seguintes labels no serviço do Garage no seu `docker-compose`:
```yaml
labels:
  - "traefik.http.middlewares.garage-cors.headers.accesscontrolallowmethods=GET,POST,PUT,DELETE,OPTIONS"
  - "traefik.http.middlewares.garage-cors.headers.accesscontrolalloworiginlist=*"
  - "traefik.http.middlewares.garage-cors.headers.accesscontrolallowheaders=*"
  - "traefik.http.middlewares.garage-cors.headers.accesscontrolmaxage=3600"
  - "traefik.http.routers.garage-router.middlewares=garage-cors"
```

---

## 6. Resolução de Problemas Comuns (Troubleshooting)

*   **Erro `AuthorizationHeaderMalformed`**: A assinatura da requisição falhou. Verifique se o cliente S3 está usando a região `sa-east-1`. Qualquer outra região causará rejeição pelo Garage.
*   **Erro `SignatureDoesNotMatch`**: Credenciais incorretas. Verifique se copiou corretamente as chaves do arquivo `.env.s3`.
*   **Timeout / Host Não Encontrado**: O SDK está tentando acessar via subdomínio (`http://meu-bucket.localhost:3900`). Certifique-se de que a opção de endereçamento por caminho (Path-Style) está ativada.
*   **Erro de Credenciais Inexistentes**: O AWS CLI ou SDK não encontrou chaves. Certifique-se de exportar as variáveis com `export $(grep -v '^#' .env.s3 | xargs)` no terminal atual antes de rodar os scripts/serviços.
*   **Bloqueio de CORS**: O navegador recusa requisições para o Garage. Siga as opções de configuração descritas na seção 5 deste documento para liberar o bucket.

