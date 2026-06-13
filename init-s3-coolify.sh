#!/usr/bin/env bash

# Script para inicialização independente de credenciais S3 e Buckets no Garage (ideal para Coolify/Produção)
# Pode ser executado em qualquer diretório sem depender de docker-compose.yml.
set -e

# Configurações padrão
DEFAULT_KEY_NAME="minha-chave"
DEFAULT_BUCKET_NAME="meu-bucket"
DEFAULT_ZONE="sa-east-1a"
DEFAULT_CAPACITY="10G"
DEFAULT_REGION="sa-east-1"

# Cores para o terminal
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Sem Cor

echo -e "${BLUE}=== Inicializador Garage S3 (Independente/Coolify) ===${NC}"

# 1. Verificar se o Docker está instalado
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}Erro: O comando 'docker' não está instalado neste sistema.${NC}"
    exit 1
fi

# 2. Tentar autodetectar o container do Garage rodando
echo -e "Buscando container do Garage ativo..."
CONTAINER_NAME=""

# Filtro A: buscar por imagem dxflrs/garage
CONTAINER_NAME=$(docker ps --filter "status=running" --filter "ancestor=dxflrs/garage" --format "{{.Names}}" | head -n 1)

# Filtro B: buscar por containers que tenham "garage" no nome se o A falhar
if [ -z "$CONTAINER_NAME" ]; then
    CONTAINER_NAME=$(docker ps --filter "status=running" --filter "name=garage" --format "{{.Names}}" | head -n 1)
fi

# Parâmetros opcionais passados pelo usuário
KEY_NAME="${1:-$DEFAULT_KEY_NAME}"
BUCKET_NAME="${2:-$DEFAULT_BUCKET_NAME}"
# Opcional: Usuário pode forçar o nome do container como terceiro argumento ou via variável de ambiente
CONTAINER_NAME="${3:-${GARAGE_CONTAINER:-$CONTAINER_NAME}}"

# Validar se encontramos um container
if [ -z "$CONTAINER_NAME" ]; then
    echo -e "${RED}Erro: Não foi possível autodetectar um container do Garage rodando.${NC}"
    echo -e "Se você sabe o nome do container, execute especificando-o no terceiro argumento:"
    echo -e "Exemplo: ${YELLOW}$0 meu-key meu-bucket nome-do-container${NC}"
    exit 1
fi

echo -e "Container detectado/especificado: ${GREEN}${CONTAINER_NAME}${NC}"
echo -e "Configurando chave: ${YELLOW}${KEY_NAME}${NC}"
echo -e "Configurando bucket: ${YELLOW}${BUCKET_NAME}${NC}"
echo ""

# 3. Validar se o comando 'garage' responde no container
if ! docker exec "$CONTAINER_NAME" /garage status >/dev/null 2>&1; then
    echo -e "${RED}Erro: Não foi possível executar comandos da CLI do Garage no container '${CONTAINER_NAME}'.${NC}"
    echo -e "Verifique se o container é realmente uma instância do Garage S3 em execução.${NC}"
    exit 1
fi

# 4. Configurar e aplicar o layout do cluster caso existam nós sem papel
UNASSIGNED_NODES=$(docker exec "$CONTAINER_NAME" /garage status | grep "NO ROLE ASSIGNED" || true)

if [ -n "$UNASSIGNED_NODES" ]; then
    echo -e "${YELLOW}Aviso: Detectados nós do Garage sem papel atribuído (Layout não configurado).${NC}"
    echo -e "${BLUE}Inicializando a configuração de layout automaticamente...${NC}"
    
    # Obter a versão atual do layout
    CURRENT_VERSION=$(docker exec "$CONTAINER_NAME" /garage layout show | grep "Current cluster layout version:" | awk '{print $NF}' || echo "0")
    if [ -z "$CURRENT_VERSION" ]; then
        CURRENT_VERSION=0
    fi
    NEXT_VERSION=$((CURRENT_VERSION + 1))
    
    # Atribuir papel para cada nó não configurado
    while read -r line; do
        if [ -n "$line" ]; then
            NODE_ID=$(echo "$line" | awk '{print $1}')
            if [ -n "$NODE_ID" ]; then
                echo -e "Atribuindo capacidade de ${DEFAULT_CAPACITY} na zona '${DEFAULT_ZONE}' para o nó: ${YELLOW}${NODE_ID}${NC}"
                docker exec "$CONTAINER_NAME" /garage layout assign "$NODE_ID" -z "$DEFAULT_ZONE" -c "$DEFAULT_CAPACITY" > /dev/null
            fi
        fi
    done <<< "$UNASSIGNED_NODES"
    
    # Aplicar o layout
    echo -e "Aplicando layout versão ${NEXT_VERSION}..."
    docker exec "$CONTAINER_NAME" /garage layout apply --version "$NEXT_VERSION" > /dev/null
    echo -e "${GREEN}✔ Layout do cluster inicializado e aplicado!${NC}\n"
fi

# 5. Criar a chave
echo -e "${BLUE}[1/3] Gerando chave de acesso S3...${NC}"
KEY_OUTPUT=$(docker exec "$CONTAINER_NAME" /garage key create "$KEY_NAME")

# Extrair as chaves do output
ACCESS_KEY=$(echo "$KEY_OUTPUT" | grep -i "Key ID:" | awk '{print $3}')
SECRET_KEY=$(echo "$KEY_OUTPUT" | awk '/Secret key:/ {flag=1; printf "%s", $3; next} flag && /^[a-f0-9]+$/ {printf "%s", $0; next} flag && !/^[a-f0-9]+$/ {flag=0} END {print ""}')

# Fallback simples caso o parse falhe
if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    echo -e "${YELLOW}Aviso: Não foi possível extrair as chaves automaticamente.${NC}"
    echo -e "Aqui está o retorno completo do Garage:${NC}"
    echo "$KEY_OUTPUT"
    exit 1
fi

# 6. Criar o bucket (apenas se não existir)
if docker exec "$CONTAINER_NAME" /garage bucket info "$BUCKET_NAME" >/dev/null 2>&1; then
    echo -e "${YELLOW}Aviso: O bucket '${BUCKET_NAME}' já existe. Ignorando criação.${NC}"
else
    echo -e "${BLUE}[2/3] Criando o bucket S3...${NC}"
    docker exec "$CONTAINER_NAME" /garage bucket create "$BUCKET_NAME" > /dev/null
fi

# 7. Associar a chave ao bucket com permissões RW e owner
echo -e "${BLUE}[3/3] Vinculando permissões de leitura/escrita e owner...${NC}"
docker exec "$CONTAINER_NAME" /garage bucket allow "$BUCKET_NAME" --key "$ACCESS_KEY" --read --write --owner > /dev/null

# Tentar aplicar regra de CORS padrão no bucket via AWS CLI se disponível
if command -v aws >/dev/null 2>&1; then
    echo -e "${BLUE}Configurando regras de CORS no bucket via AWS CLI...${NC}"
    CORS_TMP=$(mktemp)
    cat <<EOF > "$CORS_TMP"
{
  "CORSRules": [
    {
      "AllowedHeaders": ["*"],
      "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
      "AllowedOrigins": ["*"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 3600
    }
  ]
}
EOF
    if AWS_ACCESS_KEY_ID="${ACCESS_KEY}" AWS_SECRET_ACCESS_KEY="${SECRET_KEY}" AWS_DEFAULT_REGION="${DEFAULT_REGION}" aws --endpoint-url http://localhost:3900 s3api put-bucket-cors --bucket "$BUCKET_NAME" --cors-configuration "file://$CORS_TMP" >/dev/null 2>&1; then
        echo -e "${GREEN}✔ CORS configurado para aceitar todas as origens (*)!${NC}"
    else
        echo -e "${YELLOW}Aviso: Não foi possível aplicar a regra de CORS via AWS CLI.${NC}"
    fi
    rm -f "$CORS_TMP"
else
    echo -e "${YELLOW}Nota: 'aws-cli' não encontrado no host. Lembre-se de configurar o CORS na aplicação ou via proxy reverso.${NC}"
fi

# 8. Exibir resultado
echo -e "\n${GREEN}✔ Configuração concluída com sucesso!${NC}\n"
echo -e "${BLUE}=====================================${NC}"
echo -e "  Container:      ${GREEN}${CONTAINER_NAME}${NC}"
echo -e "  Access Key ID:  ${GREEN}${ACCESS_KEY}${NC}"
echo -e "  Secret Key:     ${GREEN}${SECRET_KEY}${NC}"
echo -e "  Bucket Name:    ${GREEN}${BUCKET_NAME}${NC}"
echo -e "  Endpoint URL:   ${YELLOW}http://localhost:3900${NC}"
echo -e "  Region:         ${YELLOW}${DEFAULT_REGION}${NC}"
echo -e "${BLUE}=====================================${NC}"

# Salvar no arquivo local da pasta onde foi executado
ENV_S3_FILE=".env.s3"
cat <<EOF > "$ENV_S3_FILE"
# Credenciais do Garage S3 geradas em $(date)
AWS_ACCESS_KEY_ID=${ACCESS_KEY}
AWS_SECRET_ACCESS_KEY=${SECRET_KEY}
AWS_ENDPOINT_URL=http://localhost:3900
AWS_DEFAULT_REGION=${DEFAULT_REGION}
S3_BUCKET_NAME=${BUCKET_NAME}
EOF

echo -e "\nCredenciais salvas localmente em: ${YELLOW}$(pwd)/${ENV_S3_FILE}${NC}"
