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
