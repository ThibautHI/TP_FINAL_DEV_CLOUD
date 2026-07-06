#!/usr/bin/env bash

# ============================================================================
# GreenLogistics — Script de lancement (Linux / macOS)
# ============================================================================

set -euo pipefail

# Couleurs pour l'affichage
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Nom du cluster kind
CLUSTER_NAME="greenlogistics-cluster"

print_header() {
    clear
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "${GREEN}             GreenLogistics — Système de Gestion & Déploiement       ${NC}"
    echo -e "${GREEN}======================================================================${NC}"
    echo ""
}

check_prereq() {
    echo -e "${BLUE}[*] Vérification des prérequis...${NC}"
    local missing=0

    # Vérifier Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}[X] Docker n'est pas installé.${NC}"
        missing=$((missing + 1))
    else
        if ! docker info &> /dev/null; then
            echo -e "${YELLOW}[!] Docker est installé mais ne semble pas démarré. Merci de lancer Docker Desktop.${NC}"
            missing=$((missing + 1))
        else
            echo -e "${GREEN}[V] Docker est installé et en cours d'exécution.${NC}"
        fi
    fi

    # Vérifier Terraform
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}[X] Terraform n'est pas installé.${NC}"
        missing=$((missing + 1))
    else
        echo -e "${GREEN}[V] Terraform est installé ($(terraform -v | head -n 1)).${NC}"
    fi

    # Vérifier Helm
    if ! command -v helm &> /dev/null; then
        echo -e "${YELLOW}[!] Helm n'est pas installé. Requis pour le mode Kubernetes (Terraform).${NC}"
    else
        echo -e "${GREEN}[V] Helm est installé (${VER=$(helm version --short 2>/dev/null) || VER="OK"}; $VER).${NC}"
    fi

    # Vérifier kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${YELLOW}[!] kubectl n'est pas installé. Requis pour interagir avec le cluster Kubernetes.${NC}"
    else
        echo -e "${GREEN}[V] kubectl est installé.${NC}"
    fi

    # Vérifier kind
    if ! command -v kind &> /dev/null; then
        echo -e "${YELLOW}[!] kind n'est pas installé. Requis pour créer le cluster Kubernetes local.${NC}"
    else
        echo -e "${GREEN}[V] kind est installé ($(kind version | awk '{print $2}')).${NC}"
    fi

    echo ""
    if [ $missing -gt 0 ]; then
        echo -e "${YELLOW}[Attention] Certains prérequis sont manquants ou non démarrés.${NC}"
        echo -e "${YELLOW}Veuillez résoudre ces alertes avant de lancer un déploiement.${NC}"
        echo ""
    fi
}

deploy_kubernetes() {
    print_header
    echo -e "${BLUE}[*] Déploiement en Mode Kubernetes via Terraform...${NC}"
    
    # S'assurer que Docker tourne
    if ! docker info &>/dev/null; then
        echo -e "${RED}[Erreur] Le démon Docker n'est pas démarré. Impossible de créer le cluster kind.${NC}"
        read -n 1 -s -r -p "Appuyez sur n'importe quelle touche pour revenir au menu..."
        return
    fi

    # Vérifier si des conteneurs du cluster existent mais sont arrêtés
    exited_containers=$(docker ps -a --filter "name=greenlogistics-cluster" --filter "status=exited" --format "{{.Names}}" || true)
    if [ -n "$exited_containers" ]; then
        echo -e "${YELLOW}[!] Les conteneurs du cluster kind existent mais sont arrêtés (ex. après un redémarrage du PC).${NC}"
        echo -e "${BLUE}[*] Tentative de redémarrage automatique des conteneurs...${NC}"
        for container in $exited_containers; do
            docker start "$container" >/dev/null
        done
        echo -e "${GREEN}[V] Conteneurs redémarrés avec succès.${NC}"
        sleep 2
    fi

    # Initialisation des variables d'environnement des services si non existantes
    echo -e "${BLUE}[*] Initialisation des fichiers .env pour les services si nécessaire...${NC}"
    for service in delivery-service gps-ingest-service notification-service gps-simulator; do
        if [ ! -f "services/$service/.env" ] && [ -f "services/$service/.env.example" ]; then
            cp "services/$service/.env.example" "services/$service/.env"
            echo -e "    -> Créé services/$service/.env"
        fi
    done

    # Lancement de Terraform
    echo -e "${BLUE}[*] Exécution de Terraform...${NC}"
    cd terraform
    
    echo -e "    -> Initialisation de Terraform..."
    terraform init
    
    echo -e "    -> Application du plan Terraform (cela peut prendre plusieurs minutes)..."
    if terraform apply -auto-approve; then
        echo -e "${GREEN}[V] Déploiement Terraform terminé avec succès !${NC}"
        echo ""
        echo -e "${YELLOW}Prochaines étapes recommandées :${NC}"
        echo -e "1. Attendez 2-3 minutes pour que tous les Pods soient prêts ('kubectl get pods -A')"
        echo -e "2. Lancez l'option [3] du menu de ce script pour activer les accès locaux (Port-Forwarding)"
    else
        echo -e "${RED}[X] Une erreur est survenue lors de l'application de Terraform.${NC}"
    fi
    
    cd ..
    echo ""
    read -n 1 -s -r -p "Appuyez sur n'importe quelle touche pour revenir au menu..."
}

deploy_docker_compose() {
    print_header
    echo -e "${BLUE}[*] Déploiement en Mode Docker Compose...${NC}"

    # S'assurer que Docker tourne
    if ! docker info &> /dev/null; then
        echo -e "${RED}[Erreur] Le démon Docker n'est pas démarré. Impossible de lancer Docker Compose.${NC}"
        read -n 1 -s -r -p "Appuyez sur n'importe quelle touche pour revenir au menu..."
        return
    fi

    # Lancement de docker compose
    if docker compose up -d; then
        echo -e "${GREEN}[V] Tous les conteneurs ont été lancés en arrière-plan !${NC}"
        echo ""
        echo -e "${GREEN}Accès aux applications :${NC}"
        echo -e "  - Carte temps réel (Delivery Service) : http://localhost:3000"
        echo -e "  - API d'ingestion GPS                 : http://localhost:3001"
        echo -e "  - Console Redpanda (Broker Kafka)     : http://localhost:8080"
        echo -e "  - Simulateur GPS                      : http://localhost:3003"
        echo -e "  - MailHog (Serveur Mail Simulé)       : http://localhost:8025"
    else
        echo -e "${RED}[X] Une erreur est survenue lors du démarrage de Docker Compose.${NC}"
    fi

    echo ""
    read -n 1 -s -r -p "Appuyez sur n'importe quelle touche pour revenir au menu..."
}

start_port_forward() {
    print_header
    echo -e "${BLUE}[*] Configuration du Port-Forwarding Kubernetes...${NC}"

    # Vérifier que le contexte kubectl pointe bien vers notre cluster
    if ! kubectl config current-context | grep -q "kind-greenlogistics-cluster" &> /dev/null; then
        echo -e "${YELLOW}[!] Le cluster Kubernetes n'est pas configuré ou le contexte n'est pas positionné sur 'kind-greenlogistics-cluster'.${NC}"
        echo -e "    Voulez-vous quand même tenter l'exposition ? (y/n)"
        read -r ans
        if [[ ! "$ans" =~ ^[Yy]$ ]]; then
            return
        fi
    fi

    echo -e "${BLUE}[*] Fermeture des redirections de ports existantes...${NC}"
    pkill -f "port-forward" || true
    sleep 1

    echo -e "${BLUE}[*] Lancement des redirections en arrière-plan...${NC}"

    # 1. Delivery Service (Cartographie Leaflet)
    kubectl port-forward service/delivery-service -n app 8000:3000 > /tmp/pf-delivery.log 2>&1 &
    
    # 2. ArgoCD UI
    kubectl port-forward service/argocd-server -n argocd 8080:443 > /tmp/pf-argocd.log 2>&1 &

    # 3. Grafana (SLOs) - Port 3004 pour éviter le conflit avec Delivery Service
    kubectl port-forward service/kps-grafana -n monitoring 3004:80 > /tmp/pf-grafana.log 2>&1 &

    # 4. MailHog UI
    kubectl port-forward service/mailhog -n mail 8025:8025 > /tmp/pf-mailhog.log 2>&1 &

    # 5. Kubecost (FinOps)
    kubectl port-forward service/kubecost-cost-analyzer -n kubecost 9090:9090 > /tmp/pf-kubecost.log 2>&1 &

    # 6. GPS Simulator API
    kubectl port-forward deployment/gps-simulator -n app 3003:3003 > /tmp/pf-simulator.log 2>&1 &

    sleep 2
    echo -e "${GREEN}[V] Redirections lancées avec succès !${NC}"
    echo ""
    echo -e "${GREEN}Liens d'accès à vos applications Kubernetes :${NC}"
    echo -e "  - 🗺️  Carte temps réel (Leaflet)     : ${BLUE}http://localhost:8000${NC}"
    echo -e "  - ⛵ ArgoCD Console Web (GitOps)     : ${BLUE}https://localhost:8080${NC} (admin / Root123! ou MDP généré)"
    echo -e "  - 📊 Grafana (Monitoring & SLOs)     : ${BLUE}http://localhost:3004${NC}"
    echo -e "  - ✉️  MailHog (Simulateur d'e-mails)   : ${BLUE}http://localhost:8025${NC}"
    echo -e "  - 💰 Kubecost (Analyse FinOps)       : ${BLUE}http://localhost:9090${NC}"
    echo ""
    echo -e "${YELLOW}Note : Les redirections tournent en tâche de fond.${NC}"
    echo -e "${YELLOW}Pour les arrêter, relancez cette option ou nettoyez l'infrastructure.${NC}"
    echo ""
    read -n 1 -s -r -p "Appuyez sur n'importe quelle touche pour revenir au menu..."
}

cleanup() {
    print_header
    echo -e "${YELLOW}[!] Procédure de nettoyage de l'infrastructure...${NC}"
    
    # Arrêt des redirections
    echo -e " -> Arrêt des port-forwards en arrière-plan..."
    pkill -f "port-forward" || true

    echo -e " -> Que souhaitez-vous supprimer ?${NC}"
    echo -e "    1. Cluster Kubernetes (kind) uniquement"
    echo -e "    2. Environnement Docker Compose uniquement"
    echo -e "    3. Tout nettoyer (K8s + Docker Compose + états Terraform)"
    echo -e "    4. Retour au menu"
    echo -n "Votre choix : "
    read -r clean_choice

    case $clean_choice in
        1)
            echo -e "${BLUE}[*] Suppression du cluster kind...${NC}"
            kind delete cluster --name greenlogistics-cluster || true
            ;;
        2)
            echo -e "${BLUE}[*] Arrêt de Docker Compose...${NC}"
            docker compose down -v || true
            ;;
        3)
            echo -e "${BLUE}[*] Suppression du cluster kind...${NC}"
            kind delete cluster --name greenlogistics-cluster || true
            echo -e "${BLUE}[*] Arrêt de Docker Compose...${NC}"
            docker compose down -v || true
            echo -e "${BLUE}[*] Suppression des fichiers d'état Terraform locaux...${NC}"
            rm -f terraform/terraform.tfstate terraform/terraform.tfstate.backup terraform/plan.tfplan || true
            rm -rf terraform/.terraform || true
            echo -e "${GREEN}[V] Nettoyage complet effectué !${NC}"
            ;;
        *)
            return
            ;;
    esac

    echo ""
    read -n 1 -s -r -p "Appuyez sur n'importe quelle touche pour revenir au menu..."
}

# Boucle principale
while true; do
    print_header
    check_prereq
    
    echo -e "${BLUE}Menu de déploiement :${NC}"
    echo -e "  [1] Lancer le projet via Kubernetes & Terraform (Standard / Production)"
    echo -e "  [2] Lancer le projet via Docker Compose (Léger / Développement)"
    echo -e "  [3] Activer les accès locaux / Port-Forwarding (Mode Kubernetes)"
    echo -e "  [4] Nettoyer / Arrêter l'infrastructure"
    echo -e "  [5] Quitter"
    echo ""
    echo -n "Veuillez choisir une option (1-5) : "
    read -r choice

    case $choice in
        1) deploy_kubernetes ;;
        2) deploy_docker_compose ;;
        3) start_port_forward ;;
        4) cleanup ;;
        5) 
            echo -e "${GREEN}Au revoir !${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Option invalide.${NC}"
            sleep 1
            ;;
    esac
done
