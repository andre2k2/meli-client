#!/bin/bash

# Script para autenticação OAuth 2.0 no Mercado Livre
# Recupera access_token após login interativo

# Configuração - EDITE ESTAS VARIÁVEIS
CLIENT_ID=""
CLIENT_SECRET=""
REDIRECT_URI="https://meusite.com/callback"  # URL de callback simples para testes
STATE="ml_auth_$(date +%s)"
SCOPE="read write offline_access"

# URLs da API do Mercado Livre
ML_AUTH_URL="https://auth.mercadolivre.com.br/authorization"
ML_TOKEN_URL="https://api.mercadolibre.com/oauth/token"
TEST_TOKEN_URL="https://api.mercadolibre.com/users/me"

# Arquivo para salvar tokens
TOKEN_FILE="$HOME/.mercadolivre_tokens"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para exibir ajuda
show_help() {
    echo "Script de autenticação OAuth 2.0 para Mercado Livre"
    echo
    echo "Uso: $0 [opções]"
    echo
    echo "Opções:"
    echo "  -i, --client-id ID        Client ID da sua aplicação"
    echo "  -s, --client-secret SEC   Client Secret da sua aplicação"  
    echo "  -r, --redirect-uri URI    URI de redirecionamento (padrão: https://httpbin.org/get)"
    echo "  -c, --config FILE         Arquivo de configuração"
    echo "  -t, --token-file FILE     Arquivo para salvar tokens (padrão: ~/.mercadolivre_tokens)"
    echo "  -h, --help                Mostra esta ajuda"
    echo "      --refresh             Renova o access token usando o refresh token salvo"
    echo "      --check               Verifica se o token salvo ainda é válido"
    echo "      --test                Testa o token atual fazendo uma chamada à API de usuário"
    echo
    echo "Exemplo:"
    echo "  $0 -i APP123456 -s secret123 -r https://meusite.com/callback"
    echo
    echo "Ou crie um arquivo de configuração:"
    echo "  CLIENT_ID=APP123456"
    echo "  CLIENT_SECRET=secret123"
    echo "  REDIRECT_URI=https://meusite.com/callback"
}

# Função para carregar configuração de arquivo
load_config() {
    if [ -f "$1" ]; then
        echo -e "${BLUE}Carregando configuração de $1...${NC}"
        source "$1"
    else
        echo -e "${RED}Arquivo de configuração não encontrado: $1${NC}"
        exit 1
    fi
}

# Função para validar configuração
validate_config() {
    if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
        echo -e "${RED}Erro: CLIENT_ID e CLIENT_SECRET são obrigatórios${NC}"
        echo "Use $0 --help para ver as opções"
        exit 1
    fi
}

# Função para gerar URL de autorização
generate_auth_url() {
    local auth_url="${ML_AUTH_URL}?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&state=${STATE}"
    
    if [ -n "$SCOPE" ]; then
        auth_url="${auth_url}&scope=${SCOPE}"
    fi
    
    echo "$auth_url"
}

# Função para extrair código da URL de callback
extract_code_from_url() {
    local callback_url="$1"
    
    # Extrair código usando regex
    if [[ "$callback_url" =~ code=([^&]*) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Função para extrair state da URL de callback
extract_state_from_url() {
    local callback_url="$1"
    
    if [[ "$callback_url" =~ state=([^&]*) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Função para trocar código por token
exchange_code_for_token() {
    local auth_code="$1"
    
    echo -e "${BLUE}Trocando código por access token...${NC}"
    
    # Imprimir comando curl
    echo -e "${YELLOW}Comando CURL:${NC} curl -s -X POST \"$ML_TOKEN_URL\" -H 'Content-Type: application/x-www-form-urlencoded' -d 'grant_type=authorization_code' -d 'client_id=$CLIENT_ID' -d 'client_secret=$CLIENT_SECRET' -d 'code=$auth_code' -d 'redirect_uri=$REDIRECT_URI'"
    
    local response=$(curl -s -X POST "$ML_TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=authorization_code" \
        -d "client_id=$CLIENT_ID" \
        -d "client_secret=$CLIENT_SECRET" \
        -d "code=$auth_code" \
        -d "redirect_uri=$REDIRECT_URI")
    
    echo "$response"
}

# Função para salvar tokens
save_tokens() {
    local token_response="$1"
    
    # Extrair informações do JSON (usando métodos básicos)
    local access_token=$(echo "$token_response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    local refresh_token=$(echo "$token_response" | grep -o '"refresh_token":"[^"]*' | cut -d'"' -f4)
    local expires_in=$(echo "$token_response" | grep -o '"expires_in":[^,}]*' | cut -d':' -f2)
    local token_type=$(echo "$token_response" | grep -o '"token_type":"[^"]*' | cut -d'"' -f4)
    
    if [ -n "$access_token" ]; then
        local expires_at=$(($(date +%s) + expires_in))
        
        # Salvar tokens em arquivo
        cat > "$TOKEN_FILE" << EOF
# Tokens do Mercado Livre - Gerado em $(date)
ACCESS_TOKEN="$access_token"
REFRESH_TOKEN="$refresh_token"
TOKEN_TYPE="$token_type"
EXPIRES_IN=$expires_in
EXPIRES_AT=$expires_at
CLIENT_ID="$CLIENT_ID"
CLIENT_SECRET="$CLIENT_SECRET"
EOF
        
        chmod 600 "$TOKEN_FILE"
        echo -e "${GREEN}Tokens salvos em: $TOKEN_FILE${NC}"
        
        # Mostrar informações
        echo -e "${GREEN}✓ Access Token obtido com sucesso!${NC}"
        echo -e "${YELLOW}Access Token:${NC} $access_token"
        echo -e "${YELLOW}Refresh Token:${NC} $refresh_token"
        echo -e "${YELLOW}Expira em:${NC} $expires_in segundos ($(date -d "@$expires_at"))"
        
        return 0
    else
        echo -e "${RED}Erro ao obter access token:${NC}"
        echo "$token_response"
        return 1
    fi
}

# Função para renovar token
refresh_access_token() {
    if [ ! -f "$TOKEN_FILE" ]; then
        echo -e "${RED}Arquivo de tokens não encontrado: $TOKEN_FILE${NC}"
        return 1
    fi
    
    source "$TOKEN_FILE"
    
    if [ -z "$REFRESH_TOKEN" ]; then
        echo -e "${RED}Refresh token não encontrado${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Renovando access token...${NC}"
    
    # Imprimir comando curl
    echo -e "${YELLOW}Comando CURL:${NC} curl -s -X POST \"$ML_TOKEN_URL\" -H 'Content-Type: application/x-www-form-urlencoded' -d 'grant_type=refresh_token' -d 'client_id=$CLIENT_ID' -d 'client_secret=$CLIENT_SECRET' -d 'refresh_token=$REFRESH_TOKEN'"
    
    local response=$(curl -s -X POST "$ML_TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=refresh_token" \
        -d "client_id=$CLIENT_ID" \
        -d "client_secret=$CLIENT_SECRET" \
        -d "refresh_token=$REFRESH_TOKEN")
    
    save_tokens "$response"
}

# Função para verificar se token é válido
check_token_validity() {
    if [ ! -f "$TOKEN_FILE" ]; then
        echo -e "${YELLOW}Nenhum token encontrado${NC}"
        return 1
    fi
    
    source "$TOKEN_FILE"
    
    if [ -z "$ACCESS_TOKEN" ]; then
        echo -e "${RED}Access token não encontrado${NC}"
        return 1
    fi
    
    local current_time=$(date +%s)
    
    if [ "$current_time" -gt "$EXPIRES_AT" ]; then
        echo -e "${YELLOW}Token expirado${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Token válido até $(date -d "@$EXPIRES_AT")${NC}"
    return 0
}

# Função para testar token
test_token() {
    if [ ! -f "$TOKEN_FILE" ]; then
        echo -e "${RED}Arquivo de tokens não encontrado: $TOKEN_FILE${NC}"
        return 1
    fi
    
    source "$TOKEN_FILE"
    
    echo -e "${BLUE}Testando token...${NC}"
    
    # Imprimir comando curl
    echo -e "${YELLOW}Comando CURL:${NC} curl -s -H 'Authorization: Bearer $ACCESS_TOKEN' '$TEST_TOKEN_URL'"
    
    local response=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$TEST_TOKEN_URL")
    
    local user_id=$(echo "$response" | grep -o '"id":[^,}]*' | head -1 | cut -d':' -f2)
    
    if [ -n "$user_id" ]; then
        echo -e "${GREEN}✓ Token válido!${NC}"
        echo -e "${YELLOW}User ID:${NC} $user_id"
        echo "$response"
    else
        echo -e "${RED}Token inválido ou expirado${NC}"
        echo "$response"
    fi
}

# Função principal de autenticação
main_auth() {
    echo -e "${BLUE}=== Autenticação OAuth 2.0 - Mercado Livre ===${NC}"
    echo
    
    # Gerar URL de autorização
    local auth_url=$(generate_auth_url)
    
    echo -e "${YELLOW}1. Abrindo URL de autorização no navegador...${NC}"
    echo "URL: $auth_url"
    echo
    
    # Abrir no navegador
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$auth_url"
    elif command -v open >/dev/null 2>&1; then
        open "$auth_url"
    elif command -v start >/dev/null 2>&1; then
        start "$auth_url"
    else
        echo -e "${YELLOW}Não foi possível abrir automaticamente. Copie e cole a URL acima no navegador.${NC}"
    fi
    
    echo -e "${YELLOW}2. Faça login no Mercado Livre e autorize a aplicação${NC}"
    echo -e "${YELLOW}3. Após autorizar, você será redirecionado para a URL de callback${NC}"
    echo
    echo -e "${BLUE}Cole aqui a URL completa para onde foi redirecionado:${NC}"
    read -r callback_url
    
    # Extrair código e state
    local auth_code=$(extract_code_from_url "$callback_url")
    local returned_state=$(extract_state_from_url "$callback_url")
    
    # Validar state
    if [ "$returned_state" != "$STATE" ]; then
        echo -e "${RED}Erro: State inválido. Possível ataque CSRF.${NC}"
        exit 1
    fi
    
    if [ -z "$auth_code" ]; then
        echo -e "${RED}Erro: Código de autorização não encontrado na URL${NC}"
        echo "Verifique se a URL está completa e correta"
        exit 1
    fi
    
    echo -e "${GREEN}Código de autorização extraído: $auth_code${NC}"
    
    # Trocar código por token
    local token_response=$(exchange_code_for_token "$auth_code")
    
    # Salvar tokens
    if save_tokens "$token_response"; then
        echo -e "${GREEN}✓ Autenticação concluída com sucesso!${NC}"
        
        # Testar token
        echo
        test_token
    else
        exit 1
    fi
}

# Processar argumentos da linha de comando
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--client-id)
            CLIENT_ID="$2"
            shift 2
            ;;
        -s|--client-secret)
            CLIENT_SECRET="$2"
            shift 2
            ;;
        -r|--redirect-uri)
            REDIRECT_URI="$2"
            shift 2
            ;;
        -c|--config)
            load_config "$2"
            shift 2
            ;;
        -t|--token-file)
            TOKEN_FILE="$2"
            shift 2
            ;;
        --refresh)
            refresh_access_token
            exit $?
            ;;
        --check)
            check_token_validity
            exit $?
            ;;
        --test)
            test_token
            exit $?
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Opção desconhecida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validar configuração
validate_config

# Verificar se já existe token válido
if check_token_validity; then
    echo -e "${YELLOW}Token válido encontrado. Deseja renovar? (y/N)${NC}"
    read -r renew
    
    if [[ "$renew" =~ ^[Yy]$ ]]; then
        refresh_access_token
    else
        echo -e "${GREEN}Usando token existente${NC}"
        test_token
    fi
else
    # Iniciar processo de autenticação
    main_auth
fi
