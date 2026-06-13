#!/usr/bin/env bash

# Script para inicialização de credenciais S3 e Buckets no Garage
set -e

# Configurações padrão
DEFAULT_KEY_NAME="minha-chave"
DEFAULT_BUCKET_NAME="meu-bucket"
DEFAULT_ZONE="sa-east-1a"
DEFAULT_CAPACITY="10G"
# ATENÇÃO: Esta região DEVE ser idêntica ao valor de 's3_region' configurado no garage.toml.
# Caso contrário, ocorrerá o erro 'AuthorizationHeaderMalformed' na assinatura das requisições S3.
DEFAULT_REGION="sa-east-1"

# Cores para o terminal
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Sem Cor

echo -e "${BLUE}=== Inicializador do Garage S3 ===${NC}"

# 1. Verificar se o docker-compose está instalado e o container está rodando
# 1. Detectar comando docker compose correto
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif docker-compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo -e "${RED}Erro: 'docker compose' ou 'docker-compose' não está instalado.${NC}"
    exit 1
fi

# 2. Verificar se o container está rodando
if ! $DOCKER_COMPOSE_CMD ps --format json | grep -q '"State":"running"'; then
    echo -e "${RED}Erro: O container 'garage' não parece estar em execução.${NC}"
    echo -e "Por favor, inicie o container primeiro rodando: ${YELLOW}$DOCKER_COMPOSE_CMD up -d${NC}"
    exit 1
fi

# 2. Configurar e aplicar o layout do cluster caso não esteja pronto
UNASSIGNED_NODES=$($DOCKER_COMPOSE_CMD exec -T garage /garage status | grep "NO ROLE ASSIGNED" || true)

if [ -n "$UNASSIGNED_NODES" ]; then
    echo -e "${YELLOW}Aviso: Detectados nós do Garage sem papel atribuído (Layout não configurado).${NC}"
    echo -e "${BLUE}Inicializando a configuração de layout automaticamente...${NC}"
    
    # Obter a versão atual do layout
    CURRENT_VERSION=$($DOCKER_COMPOSE_CMD exec -T garage /garage layout show | grep "Current cluster layout version:" | awk '{print $NF}' || echo "0")
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
                $DOCKER_COMPOSE_CMD exec -T garage /garage layout assign "$NODE_ID" -z "$DEFAULT_ZONE" -c "$DEFAULT_CAPACITY" > /dev/null
            fi
        fi
    done <<< "$UNASSIGNED_NODES"
    
    # Aplicar o layout
    echo -e "Aplicando layout versão ${NEXT_VERSION}..."
    $DOCKER_COMPOSE_CMD exec -T garage /garage layout apply --version "$NEXT_VERSION" > /dev/null
    echo -e "${GREEN}✔ Layout do cluster inicializado e aplicado!${NC}\n"
fi

# 3. Ler parâmetros ou usar padrões
KEY_NAME="${1:-$DEFAULT_KEY_NAME}"
BUCKET_NAME="${2:-$DEFAULT_BUCKET_NAME}"

echo -e "Configurando chave: ${YELLOW}${KEY_NAME}${NC}"
echo -e "Configurando bucket: ${YELLOW}${BUCKET_NAME}${NC}"
echo ""

# 3. Criar a chave
echo -e "${BLUE}[1/3] Gerando chave de acesso S3...${NC}"
KEY_OUTPUT=$($DOCKER_COMPOSE_CMD exec -T garage /garage key create "$KEY_NAME")

# Extrair as chaves do output
ACCESS_KEY=$(echo "$KEY_OUTPUT" | grep -i "Key ID:" | awk '{print $3}')
# O Secret Key pode vir quebrado em linhas dependendo do terminal, vamos pegar o valor após "Secret key:"
SECRET_KEY=$(echo "$KEY_OUTPUT" | awk '/Secret key:/ {flag=1; printf "%s", $3; next} flag && /^[a-f0-9]+$/ {printf "%s", $0; next} flag && !/^[a-f0-9]+$/ {flag=0} END {print ""}')

# Fallback simples caso o parse falhe
if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    echo -e "${YELLOW}Aviso: Não foi possível extrair as chaves automaticamente.${NC}"
    echo -e "Aqui está o retorno completo do Garage:${NC}"
    echo "$KEY_OUTPUT"
    exit 1
fi

# 4. Criar o bucket (apenas se não existir)
if $DOCKER_COMPOSE_CMD exec -T garage /garage bucket info "$BUCKET_NAME" >/dev/null 2>&1; then
    echo -e "${YELLOW}Aviso: O bucket '${BUCKET_NAME}' já existe. Ignorando criação.${NC}"
else
    echo -e "${BLUE}[2/3] Criando o bucket S3...${NC}"
    $DOCKER_COMPOSE_CMD exec -T garage /garage bucket create "$BUCKET_NAME" > /dev/null
fi

# 5. Associar a chave ao bucket
echo -e "${BLUE}[3/3] Vinculando permissões de leitura/escrita...${NC}"
$DOCKER_COMPOSE_CMD exec -T garage /garage bucket allow "$BUCKET_NAME" --key "$ACCESS_KEY" --read --write > /dev/null

# 6. Exibir resultado
echo -e "\n${GREEN}✔ Configuração concluída com sucesso!${NC}\n"
echo -e "${BLUE}=====================================${NC}"
echo -e "  Access Key ID:  ${GREEN}${ACCESS_KEY}${NC}"
echo -e "  Secret Key:     ${GREEN}${SECRET_KEY}${NC}"
echo -e "  Bucket Name:    ${GREEN}${BUCKET_NAME}${NC}"
echo -e "  Endpoint URL:   ${YELLOW}http://localhost:3900${NC}"
echo -e "  Region:         ${YELLOW}${DEFAULT_REGION}${NC}"
echo -e "${BLUE}=====================================${NC}"

# Salvar no arquivo local para facilitar a importação
ENV_S3_FILE=".env.s3"
cat <<EOF > "$ENV_S3_FILE"
# Credenciais do Garage S3 geradas em $(date)
AWS_ACCESS_KEY_ID=${ACCESS_KEY}
AWS_SECRET_ACCESS_KEY=${SECRET_KEY}
AWS_ENDPOINT_URL=http://localhost:3900
AWS_DEFAULT_REGION=${DEFAULT_REGION}
S3_BUCKET_NAME=${BUCKET_NAME}
EOF

echo -e "\nCredenciais salvas em: ${YELLOW}${ENV_S3_FILE}${NC}"
