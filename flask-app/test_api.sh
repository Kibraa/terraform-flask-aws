#!/bin/bash
# ============================================================================
# test_api.sh — Script de test automatisé de l'API Flask
# ============================================================================
# Usage : ./test_api.sh <IP_PUBLIQUE_EC2>
# Exemple : ./test_api.sh 52.47.123.45
# ============================================================================

set -e

# Couleurs pour le terminal
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Vérifier l'argument
if [ -z "$1" ]; then
    echo -e "${RED}Usage : ./test_api.sh <IP_PUBLIQUE_EC2>${NC}"
    echo "Exemple : ./test_api.sh 52.47.123.45"
    exit 1
fi

BASE_URL="http://$1"
PASS=0
FAIL=0

# Fonction de test
test_endpoint() {
    local method=$1
    local endpoint=$2
    local description=$3
    local data=$4
    local expected_code=$5

    echo -e "\n${BLUE}━━━ TEST : $description ━━━${NC}"
    echo -e "  ${method} ${endpoint}"

    if [ "$method" == "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" "$BASE_URL$endpoint")
    elif [ "$method" == "POST" ] && [ -n "$data" ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL$endpoint" $data)
    elif [ "$method" == "PUT" ]; then
        response=$(curl -s -w "\n%{http_code}" -X PUT "$BASE_URL$endpoint" \
            -H "Content-Type: application/json" -d "$data")
    elif [ "$method" == "DELETE" ]; then
        response=$(curl -s -w "\n%{http_code}" -X DELETE "$BASE_URL$endpoint")
    fi

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" == "$expected_code" ]; then
        echo -e "  ${GREEN}✓ PASS${NC} (HTTP $http_code)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗ FAIL${NC} (attendu: $expected_code, reçu: $http_code)"
        FAIL=$((FAIL + 1))
    fi

    echo "  Réponse : $(echo $body | head -c 200)"
    echo "$body"  # Retourner le body pour utilisation
}

echo -e "${YELLOW}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   TESTS API - Flask Cloud App                   ║"
echo "║   Serveur : $BASE_URL"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ──────────────────────────────────────
# Test 1 : Page d'accueil
# ──────────────────────────────────────
test_endpoint "GET" "/" "Page d'accueil" "" "200"

# ──────────────────────────────────────
# Test 2 : Health check
# ──────────────────────────────────────
test_endpoint "GET" "/api/health" "Health Check" "" "200"

# ──────────────────────────────────────
# Test 3 : Lister les fichiers (vide)
# ──────────────────────────────────────
test_endpoint "GET" "/api/files" "Lister fichiers (initial)" "" "200"

# ──────────────────────────────────────
# Test 4 : Upload d'un fichier
# ──────────────────────────────────────
echo "test content for upload" > /tmp/test_upload.txt
UPLOAD_RESPONSE=$(test_endpoint "POST" "/api/files/upload" "Upload fichier" \
    "-F file=@/tmp/test_upload.txt -F category=uploads -F description=Fichier de test" "201")

# Extraire le file ID de la réponse
FILE_ID=$(echo "$UPLOAD_RESPONSE" | grep -o '"id": "[^"]*"' | head -1 | cut -d'"' -f4)
echo -e "\n  ${BLUE}File ID extrait : $FILE_ID${NC}"

if [ -n "$FILE_ID" ]; then
    # ──────────────────────────────────────
    # Test 5 : Récupérer le fichier par ID
    # ──────────────────────────────────────
    test_endpoint "GET" "/api/files/$FILE_ID" "Récupérer fichier par ID" "" "200"

    # ──────────────────────────────────────
    # Test 6 : Modifier les métadonnées
    # ──────────────────────────────────────
    test_endpoint "PUT" "/api/files/$FILE_ID" "Modifier description" \
        '{"description": "Description modifiée par le test"}' "200"

    # ──────────────────────────────────────
    # Test 7 : URL de téléchargement
    # ──────────────────────────────────────
    test_endpoint "GET" "/api/files/$FILE_ID/download" "URL de téléchargement S3" "" "200"

    # ──────────────────────────────────────
    # Test 8 : Supprimer le fichier
    # ──────────────────────────────────────
    test_endpoint "DELETE" "/api/files/$FILE_ID" "Supprimer fichier" "" "200"
fi

# ──────────────────────────────────────
# Test 9 : Lister les objets S3
# ──────────────────────────────────────
test_endpoint "GET" "/api/s3/list" "Lister objets S3" "" "200"

# ──────────────────────────────────────
# Résumé
# ──────────────────────────────────────
echo -e "\n${YELLOW}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   RÉSULTATS                                     ║"
echo "╠══════════════════════════════════════════════════╣"
echo -e "║   ${GREEN}Réussis : $PASS${YELLOW}                                  ║"
echo -e "║   ${RED}Échoués : $FAIL${YELLOW}                                  ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# Nettoyage
rm -f /tmp/test_upload.txt

if [ $FAIL -gt 0 ]; then
    exit 1
fi
