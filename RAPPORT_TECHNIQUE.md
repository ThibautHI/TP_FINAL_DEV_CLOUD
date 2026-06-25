# Rapport Technique — Projet GreenLogistics

*Master 2 · Développer pour le Cloud*  
*Equipe : GreenLogistics (Sujet A)*  
*Auteurs : Thibaut & L'équipe*  
*Date : Juin 2026*  

---

## 1. Introduction & Contexte Métier

**GreenLogistics** est une startup fictive spécialisée dans la livraison écologique du dernier kilomètre. Notre objectif est de proposer un service de suivi en temps réel des colis, d'ingérer des coordonnées GPS à fréquence soutenue, d'avertir automatiquement les destinataires lorsque le livreur approche de sa destination, et d'offrir une interface cartographique interactive aux gestionnaires de flotte.

### Objectifs Clés :
* **Fiabilité** : Ingestions GPS continues (une position toutes les 5 secondes par livreur actif) sans perte de données.
* **Réactivité** : Notification par e-mail en moins de 10 secondes dès que le colis passe sous le seuil de 500m de distance.
* **Sécurité** : Protection des données clients (RGPD) et isolation réseau.
* **Sobriété** : Stack optimisée fonctionnant sur des infrastructures locales standardisées et transposables sur le Cloud.

---

## 2. Architecture Logicielle & Choix Runtimes

L'application est découpée en **4 microservices distincts** développés avec le runtime **Bun** (compatible Node.js) :

```
                  [ Navigateur / Client Externe ]
                                |
                    ( Ingress Nginx Controller )
                       /                  \
                      /                    \
  [ delivery-service (3000) ]     [ gps-ingest-service (3001) ]
         |              \                  /
         |               \                /
     (Postgres)           ( Redpanda Topic )
                                  |
                                  |
                      [ notification-service (3002) ]
                                  |
                              (MailHog)
```

1. **`delivery-service`** : API REST de gestion des colis et portail web cartographique. Il consomme le topic de positionnement pour mettre à jour la base PostgreSQL.
2. **`gps-ingest-service`** : Point d'entrée HTTP haute performance pour les livreurs. Reçoit les points GPS et les pousse instantanément dans Redpanda.
3. **`notification-service`** : Consomme les événements de positionnement, calcule la distance à la destination et envoie un e-mail via MailHog à moins de 500 mètres.
4. **`gps-simulator`** : Simule le déplacement pas-à-pas des livreurs.

### Justification du Runtime (Bun)
Bun a été sélectionné pour sa rapidité de démarrage quasi instantanée, sa faible empreinte mémoire (~25Mo par conteneur au repos), son support natif de TypeScript/JSX et ses performances I/O supérieures à Node.js standard.

---

## 3. Infrastructure-as-Code (Terraform)

L'entièreté de la plateforme est déclarée via Terraform dans le dossier [terraform/](file:///c:/Users/thibh/Documents/1-Informatique/M2/developper_pour_le_cloud/TP_FINAL/terraform/).

### Composants gérés par IaC :
* **Cluster K8s Local** : Utilisation du provider `tehcyx/kind` pour créer un cluster Kubernetes à 3 nœuds (1 control-plane, 2 workers) avec redirection des ports HTTP (80/443), ArgoCD (30080) et Grafana (30090).
* **Namespaces** : Isolation logique de la plateforme (`db`, `messaging`, `monitoring`, `vault`, `external-secrets`, `argocd`, `mail`, `app`).
* **Helm Releases** : Déploiement unifié via un module réutilisable maison `helm_deployment` des briques de base :
  * Ingress Nginx Controller
  * Cert-Manager
  * HashiCorp Vault (Secrets)
  * External Secrets Operator
  * Redpanda (Messaging)
  * PostgreSQL (Database)
  * Kube-Prometheus-Stack & Loki (Observabilité)
  * Linkerd Control Plane (Service Mesh)
  * Argo Rollouts & ArgoCD (Déploiement)

---

## 4. Pipeline CI/CD & DevSecOps

### Intégration Continue (GitHub Actions)
Le pipeline défini dans [ci.yml](file:///c:/Users/thibh/Documents/1-Informatique/M2/developper_pour_le_cloud/TP_FINAL/.github/workflows/ci.yml) réalise les étapes de validation sur chaque push vers `develop` ou `main` :
1. **Lancement des tests unitaires** natifs Bun.
2. **Compilation multi-stage** des images de production.
3. **Publication sur GitHub Container Registry (GHCR)**.
4. **Scan de vulnérabilités Trivy** : Le pipeline échoue immédiatement en cas de CVE `HIGH` ou `CRITICAL` non corrigée.

### Gestion SecOps des secrets
* **HashiCorp Vault** est le référentiel unique de secrets.
* **External Secrets Operator (ESO)** extrait automatiquement les secrets de Vault et génère des secrets natifs K8s `api-secret` dans le namespace `app`.
* Les applications chargent ces variables d'environnement de manière sécurisée en production sans jamais exposer les clés API de Vault.

---

## 5. GitOps & Déploiement Progressif

### ArgoCD & App-of-Apps
ArgoCD est configuré avec une application racine `root-apps` pointant vers le dossier `gitops/` de la branche `develop`. Toute modification poussée sur cette branche est automatiquement répercutée sur le cluster (Self-Heal activé).

### Argo Rollouts (Canary)
Pour le déploiement de `delivery-service`, nous remplaçons le Deployment classique par un **`Rollout`** :
* **Stratégie Canary** : Lors d'une mise à jour de version, 20% du trafic est routé vers la nouvelle version pour validation, avant de basculer à 50% puis 100%. Cela évite les pannes globales.

---

## 6. Observabilité SRE (SLIs / SLOs)

Nous avons défini 2 SLOs clés basés sur les Golden Signals de Google SRE :

1. **Taux de succès des requêtes HTTP** (`SLO >= 99%`) :
   * Mesuré par : `slo:delivery_service_http_success_rate`
   * Alerte : Déclenchée si le taux descend sous 99% pendant plus de 2 minutes.
2. **Latence HTTP P95** (`SLO < 200ms`) :
   * Visualisé sur le tableau de bord personnalisé Grafana.

Les alertes de dégradation sont envoyées par Alertmanager directement à **MailHog** pour simulation de notification de l'équipe SRE.
Loki et Promtail centralisent l'ensemble des logs pour permettre de corréler les incidents en un seul clic sur Grafana.

---

## 7. Gouvernance FinOps Locale

Sur notre stack 100% locale, le "coût" financier est représenté par l'utilisation de la RAM et du CPU de la machine hôte. 
* **Kubecost** est déployé pour fournir une analyse en temps réel de la consommation par namespace et par pod.
* Des **Resource Requests/Limits** strictes ont été configurées sur chaque composant pour garantir que la RAM du cluster ne dépasse pas **9 Go** en pleine charge, permettant une exécution confortable sur un ordinateur portable standard de 16 Go de RAM.

---

## 8. Retour d'Expérience (REX)

### Ce qui a bien fonctionné :
* La centralisation de la configuration de plateforme avec **Terraform** a grandement simplifié le déploiement.
* L'écriture des manifests applicatifs dans le même dépôt Git simplifie le cycle de boucle de rétroaction.
* **Linkerd** a fourni du mTLS automatique instantané sans la complexité de configuration d'un Service Mesh lourd comme Istio.

### Difficultés rencontrées :
* **Temps de démarrage de Redpanda** : Au premier démarrage du cluster local, Redpanda met parfois plus de 2 minutes à être prêt, ce qui peut bloquer le démarrage initial des applications clientes. Des probes de readiness et des stratégies de reconnexion automatique ont dû être implémentées dans le code Bun.
* **Liaison OIDC GitHub/Kind** : Remplacée localement par le pattern GitOps (ArgoCD tire les changements depuis GitHub sans que la CI n'ait besoin de se connecter directement au cluster kind).
