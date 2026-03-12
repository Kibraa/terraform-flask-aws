#!/bin/bash
# ============================================================================
# deploy.sh — Script de déploiement rapide
# ============================================================================
# Ce script automatise les commandes Terraform courantes.
# Usage : ./scripts/deploy.sh [init|plan|apply|destroy|output|ssh|test]
# ============================================================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

TF_DIR="terraform"
ACTION=${1:-help}

banner() {
    echo -e "${YELLOW}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║   Terraform Flask AWS — Outil de Déploiement    ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_tfvars() {
    if [ ! -f "$TF_DIR/terraform.tfvars" ]; then
        echo -e "${RED}ERREUR : Le fichier terraform/terraform.tfvars n'existe pas !${NC}"
        echo "Créez-le à partir de l'exemple :"
        echo "  cp terraform/terraform.tfvars.example terraform/terraform.tfvars"
        echo "  nano terraform/terraform.tfvars"
        exit 1
    fi
}

banner

case $ACTION in
    init)
        echo -e "${BLUE}▸ Initialisation de Terraform...${NC}"
        cd $TF_DIR && terraform init
        echo -e "${GREEN}✓ Initialisation terminée${NC}"
        ;;

    plan)
        check_tfvars
        echo -e "${BLUE}▸ Planification du déploiement...${NC}"
        cd $TF_DIR && terraform plan
        ;;

    apply)
        check_tfvars
        echo -e "${BLUE}▸ Déploiement de l'infrastructure...${NC}"
        cd $TF_DIR && terraform apply -auto-approve
        echo -e "\n${GREEN}✓ Déploiement terminé !${NC}"
        echo -e "${YELLOW}⏳ Attendez 2-3 minutes que la VM termine son provisioning.${NC}"
        ;;

    destroy)
        echo -e "${RED}▸ Destruction de l'infrastructure...${NC}"
        echo -e "${RED}ATTENTION : Cette action va supprimer TOUTES les ressources !${NC}"
        read -p "Êtes-vous sûr ? (yes/no) : " confirm
        if [ "$confirm" == "yes" ]; then
            cd $TF_DIR && terraform destroy -auto-approve
            echo -e "${GREEN}✓ Infrastructure détruite${NC}"
        else
            echo "Annulé."
        fi
        ;;

    output)
        echo -e "${BLUE}▸ Informations de déploiement :${NC}"
        cd $TF_DIR && terraform output
        ;;

    ssh)
        IP=$(cd $TF_DIR && terraform output -raw ec2_public_ip 2>/dev/null)
        if [ -z "$IP" ]; then
            echo -e "${RED}Impossible de récupérer l'IP. L'infrastructure est-elle déployée ?${NC}"
            exit 1
        fi
        echo -e "${BLUE}▸ Connexion SSH à $IP...${NC}"
        ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ubuntu@$IP
        ;;

    test)
        IP=$(cd $TF_DIR && terraform output -raw ec2_public_ip 2>/dev/null)
        if [ -z "$IP" ]; then
            echo -e "${RED}Impossible de récupérer l'IP. L'infrastructure est-elle déployée ?${NC}"
            exit 1
        fi
        echo -e "${BLUE}▸ Lancement des tests API sur $IP...${NC}"
        chmod +x flask-app/test_api.sh
        ./flask-app/test_api.sh $IP
        ;;

    help|*)
        echo "Usage : ./scripts/deploy.sh <commande>"
        echo ""
        echo "Commandes disponibles :"
        echo "  init     Initialiser Terraform (télécharger les plugins)"
        echo "  plan     Visualiser les changements prévus"
        echo "  apply    Déployer l'infrastructure"
        echo "  destroy  Détruire toute l'infrastructure"
        echo "  output   Afficher les informations de déploiement"
        echo "  ssh      Se connecter en SSH à la VM"
        echo "  test     Lancer les tests de l'API"
        echo "  help     Afficher cette aide"
        ;;
esac
