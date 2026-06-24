# GreenLogistics — Tracking Temps Réel de Livraison Dernière Mile

Ce dépôt contient le code source et les configurations d'infrastructure pour le projet **GreenLogistics** (Sujet A du TP Final - Développer pour le Cloud).

Le projet est conçu pour s'exécuter entièrement en local sur un cluster Kubernetes `kind` (en production/soutenance) ou via `docker-compose` (en développement local).

---

## 1. Architecture Applicative

L'application est composée de 4 microservices développés avec le runtime **Bun** (compatible Node.js) :

1. **`delivery-service`** (Port `3000`) : API REST de gestion des colis et Dashboard cartographique temps réel (Leaflet). Il intègre un consommateur Kafka pour sauvegarder l'historique de route dans PostgreSQL.
2. **`gps-ingest-service`** (Port `3001`) : API d'ingestion de coordonnées GPS émanant des livreurs. Les positions reçues sont publiées instantanément dans le topic Redpanda `gps-location-events`.
3. **`notification-service`** (Port `3002`) : Consomme les événements GPS. Si le livreur est détecté à moins de 500m de sa destination, il envoie un e-mail de notification au client via le serveur SMTP **MailHog** et met à jour l'état du colis.
4. **`gps-simulator`** (Port `3003`) : Script de simulation de livraison interpolant un trajet pas à pas vers la destination.

---

## 2. Démarrage de l'Infrastructure (Docker)

Assurez-vous que Docker Desktop est démarré. À la racine du projet, lancez :
```bash
docker compose up -d
```
Cette commande démarre :
- **PostgreSQL** (`port 5432`) : Stockage relationnel.
- **Redpanda** (`port 9092` & `19092`) : Broker Kafka-compatible.
- **Redpanda Console** (`http://localhost:8080`) : Interface web de supervision du broker.
- **MailHog** (`http://localhost:8025`) : Serveur SMTP et boîte mail de simulation.
- **Les 4 Applications** (`ports 3000` à `3003`).

---

## 3. Configuration des Variables d'Environnement (Mode Dev Local)

Si vous souhaitez exécuter ou modifier les microservices directement sur votre machine hôte avec **Bun**, vous devez copier les fichiers de configuration `.env.example` vers un fichier `.env` dans chaque répertoire de service.

### Sous PowerShell (Windows) :
```powershell
Copy-Item services/delivery-service/.env.example services/delivery-service/.env
Copy-Item services/gps-ingest-service/.env.example services/gps-ingest-service/.env
Copy-Item services/notification-service/.env.example services/notification-service/.env
Copy-Item services/gps-simulator/.env.example services/gps-simulator/.env
```

### Sous Linux / macOS / Git Bash :
```bash
cp services/delivery-service/.env.example services/delivery-service/.env
cp services/gps-ingest-service/.env.example services/gps-ingest-service/.env
cp services/notification-service/.env.example services/notification-service/.env
cp services/gps-simulator/.env.example services/gps-simulator/.env
```

Une fois copiés, vous pouvez installer les dépendances et démarrer les services en mode développement avec rechargement automatique :
```bash
cd services/<nom-du-service>
bun install
bun run dev
```

---

## 4. Cheat Sheet : Commandes Utiles

Voici le guide des commandes indispensables pour gérer l'infrastructure et débugger le projet en local.

### 🛠️ Terraform & Gestion de l'état
À exécuter dans le répertoire `terraform/` :

* **Générer le plan de déploiement** :
  ```bash
  terraform plan -out plan.tfplan
  ```
* **Appliquer le plan généré** :
  ```bash
  terraform apply plan.tfplan
  ```
* **Nettoyage complet à neuf (Remise à zéro)** :
  Si le cluster ou le plan Terraform se retrouvent dans un état corrompu, nettoyez tout avec ces commandes :
  ```powershell
  # 1. Supprimer le cluster local
  kind delete cluster --name greenlogistics-cluster
  
  # 2. Supprimer les fichiers d'état locaux de Terraform (PowerShell)
  Remove-Item terraform.tfstate, terraform.tfstate.backup
  
  # (Sous Linux / Git Bash)
  # rm terraform.tfstate terraform.tfstate.backup
  ```

### 🐳 Docker & Kind (Cluster Local)
* **Démarrer le cluster après un reboot de la machine** :
  Si vous venez de redémarrer Docker ou votre machine, les nœuds Kubernetes locaux sont éteints. Relancez-les :
  ```bash
  docker start greenlogistics-cluster-control-plane greenlogistics-cluster-worker greenlogistics-cluster-worker2
  ```
* **Vérifier l'état des conteneurs du cluster** :
  ```bash
  docker ps -f name=greenlogistics
  ```
* **Supprimer le cluster manuellement** :
  ```bash
  kind delete cluster --name greenlogistics-cluster
  ```

### ☸️ Kubernetes (`kubectl`)
* **Vérifier l'état du cluster et des nœuds** :
  ```bash
  kubectl get nodes
  ```
* **Lister tous les pods dans tous les namespaces** (très utile pour voir si tout tourne bien) :
  ```bash
  kubectl get pods -A
  ```
* **Surveiller les logs d'un pod en temps réel** :
  ```bash
  kubectl logs -f <nom-du-pod> -n <namespace>
  ```
* **Afficher tous les services et leurs ports exposés** :
  ```bash
  kubectl get svc -A
  ```
* **Port-Forwarding (Accès aux UIs des outils)** :
  * **ArgoCD UI** :
    ```bash
    kubectl port-forward service/argocd-server -n argocd 8080:443
    # Ouvrir ensuite : https://localhost:8080 (identifiant: admin)
    ```
  * **Grafana UI (Monitoring)** :
    ```bash
    kubectl port-forward service/kps-grafana -n monitoring 3000:80
    # Ouvrir ensuite : http://localhost:3000
    ```
  * **MailHog UI (SMTP simulé)** :
    ```bash
    kubectl port-forward service/mailhog -n mail 8025:8025
    # Ouvrir ensuite : http://localhost:8025
    ```

### ⛵ Helm (Gestion des releases)
* **Lister toutes les briques applicatives installées** :
  ```bash
  helm list -A
  ```
* **Forcer la désinstallation d'une release en conflit** :
  Si Terraform n'arrive pas à modifier une ressource (comme Redpanda ou ArgoCD), désinstallez-la proprement via Helm pour la laisser se recréer :
  ```bash
  helm uninstall <nom-de-release> -n <namespace>
  # Exemple :
  # helm uninstall redpanda -n messaging
  # helm uninstall argocd -n argocd
  ```
