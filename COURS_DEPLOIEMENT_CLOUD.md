# Cours Complet : Déploiement Cloud-Native & GitOps (TP GreenLogistics)

Ce cours a pour but de vous expliquer, avec un regard de débutant mais de manière très précise et approfondie, le fonctionnement de la stack technique moderne (Docker, Kubernetes, Terraform, ArgoCD, Vault, Linkerd, Prometheus) mise en place pour le projet **GreenLogistics**.

---

## Sommaire
1. [Introduction : Pourquoi le "Cloud-Native" ?](#1-introduction--pourquoi-le-cloud-native)
2. [Terraform : L'Infrastructure-as-Code (IaC)](#2-terraform--linfrastructure-as-code-iac)
3. [Kubernetes : L'Orchestrateur Universel](#3-kubernetes--lorchestrateur-universel)
4. [ArgoCD & le GitOps : Le Déploiement Moderne](#4-argocd--le-gitops--le-déploiement-moderne)
5. [La Sécurité : Secrets (Vault) & Service Mesh (Linkerd)](#5-la-sécurité--secrets-vault--service-mesh-linkerd)
6. [L'Observabilité & SRE : Garder le contrôle (Prometheus, Grafana, Loki)](#6-lobservabilité--sre--garder-le-contrôle-prometheus-grafana-loki)
7. [Fonctionnement Global du TP GreenLogistics](#7-fonctionnement-global-du-tp-greenlogistics)

---

## 1. Introduction : Pourquoi le "Cloud-Native" ?

### L'ancien monde : Le déploiement traditionnel
Autrefois, pour héberger une application, on achetait ou louait un serveur physique (ou une Machine Virtuelle). On s'y connectait en SSH, on installait manuellement Node.js, PostgreSQL, etc.
* **Problème** : Si le serveur plantait, tout s'arrêtait. Si la charge augmentait, il fallait manuellement configurer une autre machine (scalabilité difficile). Les environnements de développement et de production étaient souvent différents ("*Mais pourtant ça marche sur ma machine !*").

### Le nouveau monde : Le Cloud-Native
Le terme **Cloud-Native** désigne une approche de conception d'applications pensées dès le départ pour fonctionner de manière élastique et résiliente dans le Cloud.
Ses piliers sont :
1. **Les microservices** : Découper l'application en petits morceaux spécialisés (ex: un service pour les colis, un pour les mails) autonomes.
2. **La conteneurisation (Docker/Bun)** : Empaqueter l'application et toutes ses dépendances dans une boîte isolée (un conteneur) qui s'exécute de la même façon partout.
3. **L'orchestration (Kubernetes)** : Un chef d'orchestre automatique qui gère des centaines de conteneurs.

---

## 2. Terraform : L'Infrastructure-as-Code (IaC)

### 2.1 Qu'est-ce que l'IaC et pourquoi l'utiliser ?
Plutôt que d'aller sur l'interface d'un fournisseur cloud (comme Google Cloud ou AWS) et de cliquer sur des boutons pour créer des serveurs ou des bases de données, on décrit notre infrastructure sous forme de **fichiers texte (code)**.
* **Reproductibilité** : Si vous détruisez votre cluster, un simple `terraform apply` le recrée à l'identique en 5 minutes.
* **Versionnage** : L'infrastructure est stockée sur Git, on peut voir l'historique des modifications.

### 2.2 Comment fonctionne Terraform ?
Terraform utilise un langage déclaratif (le HCL). Vous écrivez l'état **cible** souhaité, et Terraform détermine lui-même les étapes à réaliser pour l'atteindre.

Il repose sur trois concepts clés :
1. **Les Providers** : Ce sont des plugins qui permettent à Terraform de discuter avec des APIs externes (ex: provider Kubernetes, provider Helm, provider Docker).
2. **Les Resources** : Les briques individuelles à créer (ex: un cluster `kind`, un namespace K8s).
3. **Le State (`terraform.tfstate`)** : C'est le "cerveau" de Terraform. C'est un fichier JSON local ou distant qui enregistre l'état réel actuel des ressources créées pour savoir quoi ajouter, modifier ou détruire lors du prochain lancement.

### 2.3 Dans notre TP
Dans le fichier [main.tf](file:///c:/Users/thibh/Documents/1-Informatique/M2/developper_pour_le_cloud/TP_FINAL/terraform/main.tf) :
* Terraform crée d'abord le cluster local **`kind`** (qui simule Kubernetes dans des conteneurs Docker sur votre PC).
* Il configure ensuite les **namespaces** (les sous-dossiers virtuels de Kubernetes).
* Enfin, il installe toutes les briques logicielles (ArgoCD, Prometheus, Redpanda, Postgres, Vault) via le gestionnaire de paquets **Helm**.

---

## 3. Kubernetes : L'Orchestrateur Universel

### 3.1 Qu'est-ce que Kubernetes (K8s) ?
Kubernetes est un système open-source qui automatise le déploiement, la mise à l'échelle (scaling) et la gestion des conteneurs applicatifs. C'est l'OS du Cloud.

### 3.2 Les ressources fondamentales de Kubernetes

```
[ Ingress (Routeur externe) ]
             |
   [ Service (IP interne stable) ]
       /          \
  [ Pod 1 ]    [ Pod 2 ]  <-- Gérés par un [ Deployment ]
```

* **Le Pod** : C'est la plus petite unité dans K8s. Un Pod enveloppe un ou plusieurs conteneurs (votre application + ses éventuels outils secondaires). Un Pod est éphémère (il peut mourir et être recréé avec une adresse IP différente).
* **Le Deployment** : C'est le gestionnaire des Pods. Vous lui dites : *"Je veux qu'il y ait toujours 2 réplicas de mon service Ingestion lancés"*. Si un Pod crash, le Deployment s'en rend compte et en recrée un immédiatement.
* **Le Service** : Comme les Pods meurent et changent d'IP, le Service fournit une adresse IP interne stable et un nom de domaine DNS unique (ex: `http://delivery-service.app.svc.cluster.local`) pour communiquer entre les applications. Il répartit aussi la charge (load balancing) entre les Pods disponibles.
* **L'Ingress** : C'est la porte d'entrée depuis l'extérieur du cluster. Il agit comme un routeur (reverse-proxy Nginx) qui redirige le trafic internet (ex: `http://localhost/` ou `/gps`) vers le bon Service interne de votre cluster.
* **Le Namespace** : Permet de cloisonner les ressources (ex: le namespace `app` pour nos codes, `db` pour Postgres, `monitoring` pour Grafana).

### 3.3 L'Autoscaling (HPA)
Dans [gps-ingest-service.yaml](file:///c:/Users/thibh/Documents/1-Informatique/M2/developper_pour_le_cloud/TP_FINAL/gitops/apps/gps-ingest-service.yaml), nous avons configuré un **HorizontalPodAutoscaler**.
Si l'utilisation du processeur (CPU) de vos pods d'ingestion dépasse 80% (à cause d'un afflux massif de livreurs GPS), Kubernetes va automatiquement démarrer de nouveaux Pods (jusqu'à 5 maximum) pour répartir la charge, puis les détruire quand le calme revient.

---

## 4. ArgoCD & le GitOps : Le Déploiement Moderne

### 4.1 Qu'est-ce que le GitOps ?
Dans le déploiement classique (Push), votre pipeline de CI (comme GitHub Actions) possède les clés d'accès administrateur de votre cluster et pousse les mises à jour. C'est un risque de sécurité (si la CI est compromise, votre cluster l'est aussi).

Le **GitOps** inverse ce paradigme (Pull) :
1. Votre Git (branche `develop`) est l'**unique source de vérité** pour l'état de votre infrastructure.
2. Un agent interne au cluster (**ArgoCD**) scrute en permanence ce dépôt Git.
3. Dès qu'il détecte un changement dans vos fichiers YAML, il tire la modification et l'applique à l'intérieur du cluster.

```
[ Développeur ] ---> Push YAML sur ---> [ GitHub (develop) ]
                                                ^
                                                | (Pull en permanence)
                                         [ Agent ArgoCD ] (Tourne dans le cluster)
                                                |
                                                v (Applique les écarts)
                                      [ Kubernetes Resources ]
```

### 4.2 L'App of Apps (Pattern Root Application)
Dans [root.yaml](file:///c:/Users/thibh/Documents/1-Informatique/M2/developper_pour_le_cloud/TP_FINAL/gitops/root.yaml), nous avons défini une application ArgoCD principale appelée `root-apps`.
Celle-ci pointe vers le répertoire `gitops/apps/`. Dès que vous ajoutez ou modifiez un fichier YAML dans ce dossier sur GitHub, ArgoCD crée automatiquement les sous-applications associées sans que vous n'ayez besoin de configurer quoi que ce soit manuellement.

### 4.3 Le Self-Heal (Auto-correction)
Si un développeur ou un attaquant tente de modifier manuellement une configuration dans le cluster via la ligne de commande (ex: `kubectl scale deploy/delivery-service --replicas=0`), ArgoCD va détecter l'écart avec Git ("Out of Sync") et corriger immédiatement l'état en repliquant le nombre correct de Pods depuis Git. C'est le **Self-Heal**.

---

## 5. La Sécurité : Secrets (Vault) & Service Mesh (Linkerd)

### 5.1 Gestion des Secrets : HashiCorp Vault + ESO
Nous ne pouvons pas stocker les mots de passe de nos bases de données dans Git.
1. Terraform démarre **HashiCorp Vault**, un coffre-fort de secrets chiffré.
2. Lors de l'initialisation ([vault_init.tf](file:///c:/Users/thibh/Documents/1-Informatique/M2/developper_pour_le_cloud/TP_FINAL/terraform/vault_init.tf)), nous insérons les secrets dans Vault.
3. L'opérateur **External Secrets Operator (ESO)** fait office de passerelle sécurisée : il lit de manière chiffrée les secrets dans Vault et génère un Secret Kubernetes standard (`api-secret`) utilisable par nos conteneurs de manière isolée.

### 5.2 Le Service Mesh (Linkerd)
Dans un cluster classique, tous les Pods peuvent se parler en clair sur le réseau interne. Si un Pod est piraté, un attaquant peut intercepter les paquets contenant les données de livraison.

Pour corriger cela, nous installons **Linkerd** :
* Linkerd injecte un conteneur léger secondaire (un proxy sidecar `linkerd-proxy`) dans chaque Pod applicatif.
* Tout le trafic entrant et sortant passe obligatoirement par ces proxys.
* Les proxys négocient automatiquement et à la volée des connexions chiffrées **mTLS (Mutual TLS)** sécurisées par certificats éphémères. L'identité de chaque pod est vérifiée cryptographiquement.

---

## 6. L'Observabilité & SRE : Garder le contrôle (Prometheus, Grafana, Loki)

Dans une architecture distribuée (plusieurs microservices qui discutent ensemble), il est très difficile de comprendre ce qui ne va pas en cas de panne sans des outils d'observabilité centralisés.

### 6.1 Les trois piliers
1. **Les Métriques (Prometheus)** : Collecter des données numériques temporelles (ex: utilisation CPU, nombre de requêtes par seconde, latences). Les applications exposent ces chiffres sur l'URL `/metrics` au format Prometheus.
2. **Les Logs (Loki + Promtail)** : Centraliser tous les journaux texte de tous les conteneurs du cluster en un seul endroit pour pouvoir rechercher facilement les erreurs.
3. **La Visualisation (Grafana)** : Fournir une interface graphique unifiée qui combine les graphiques de métriques et les logs associés.

### 6.2 Les SLOs (Service Level Objectives)
En Ingénierie SRE (Site Reliability Engineering), on définit des objectifs mesurables de qualité de service.
Dans notre fichier [rules.yaml](file:///c:/Users/thibh/Documents/1-Informatique/M2/developper_pour_le_cloud/TP_FINAL/gitops/apps/rules.yaml) :
* Nous calculons dynamiquement le taux de succès de nos services.
* Si le taux de requêtes HTTP valides (code 200/201/300) descend sous **99%** pendant plus de 2 minutes, Prometheus déclenche une alerte.
* **Alertmanager** intercepte cette alerte et l'envoie sous forme d'e-mail à notre boîte MailHog pour notifier immédiatement les ingénieurs d'astreinte.

---

## 7. Fonctionnement Global du TP GreenLogistics

Voici le cycle de vie complet de l'application lors de son exécution dans le cluster :

```
[ Navigateur ] 
      | (1) POST /parcels (Créer colis)
      v
[ delivery-service ] ---> (2) Sauvegarde dans ---> [ PostgreSQL ]
      ^
      | (5) Lit le colis créé pour lancer le trajet
[ gps-simulator ]
      | (6) POST /gps-points (Envoie les positions simulées)
      v
[ gps-ingest-service ]
      | (7) Publie l'événement de position
      v
[ Redpanda (Topic Kafka) ]
     /                  \
    / (8a) Consomme      \ (8b) Consomme
   v                      v
[ delivery-service ]   [ notification-service ]
   |                      | (9) Calcule la distance à la destination
   v (Saves route)        +--> Si < 500m ---> [ MailHog (Email Alert) ]
[ PostgreSQL ]
```

1. **Création du colis** : L'utilisateur envoie une requête HTTP à `delivery-service` pour déclarer un colis avec une adresse de destination. Le service sauvegarde le colis avec le statut `created` dans PostgreSQL.
2. **Simulation du livreur** : Le pod `gps-simulator` interroge régulièrement `delivery-service` pour trouver les colis actifs. Il commence une boucle temporelle (toutes les 5 secondes) pour simuler un déplacement physique vers les coordonnées de destination.
3. **Ingestion GPS** : À chaque étape, le simulateur envoie un point GPS (latitude, longitude) au service `gps-ingest-service`.
4. **Flux asynchrone** : `gps-ingest-service` pousse ce point GPS instantanément dans le topic Redpanda `gps-location-events`. Ce message est stocké temporairement et distribué de manière asynchrone pour ne pas ralentir le livreur.
5. **Traitement et Historique** :
   * Le service `delivery-service` lit le message de position dans Redpanda, change le statut du colis en `in_transit` et enregistre les coordonnées dans la table d'historique de trajet dans Postgres.
6. **Notification Proximité** :
   * Le service `notification-service` lit également la position en temps réel depuis Redpanda. Il calcule la distance mathématique restante jusqu'au point de livraison.
   * Si le livreur passe sous le seuil des **500 mètres**, il déclenche l'envoi d'un e-mail d'avertissement au client via le serveur MailHog.
7. **Arrivée** : À la fin de la route, le simulateur envoie une mise à jour à `delivery-service` pour marquer le colis comme `delivered`.
