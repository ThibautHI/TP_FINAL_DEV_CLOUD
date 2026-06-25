# Guide de Setup Reproductible — GreenLogistics

Ce guide explique comment reconstruire et tester l'ensemble du projet GreenLogistics sur votre machine locale en **moins de 30 minutes**.

---

## 📋 1. Prérequis

Assurez-vous d'avoir installé les outils suivants sur votre machine (cf. [Guide-Sujet.md](file:///c:/Users/thibh/Documents/1-Informatique/M2/developper_pour_le_cloud/TP_FINAL/DEMANDE/Guide-Sujet.md)) :
* **Docker Desktop** (configuré avec au moins 12 Go de RAM de préférence)
* **kubectl** (CLI Kubernetes)
* **Helm** (v3+)
* **Terraform** (1.7+)

---

## 🚀 2. Étape 1 : Provisionnement avec Terraform

Toute l'infrastructure (cluster `kind`, namespaces, charts Helm, base de données, messagerie, sécurité et observabilité) est gérée par Terraform.

1. Ouvrez un terminal dans le répertoire `terraform/` :
   ```bash
   cd terraform/
   ```
2. Initialisez les providers Terraform :
   ```bash
   terraform init
   ```
3. Appliquez le plan pour lancer la création :
   ```bash
   terraform apply -auto-approve
   ```

*Cette commande crée le cluster `kind` (3 nœuds), installe tous les opérateurs Helm (ArgoCD, Prometheus, Vault, Linkerd, etc.), initialise les secrets dans Vault et configure l'application root ArgoCD pour déployer les microservices.*

---

## ☸️ 3. Étape 2 : Vérification de la Plateforme

Une fois Terraform terminé, vérifiez que tous les composants du cluster sont bien lancés :

```bash
# Vérifier les nœuds
kubectl get nodes

# Vérifier que tous les pods d'infrastructure sont opérationnels
kubectl get pods -A
```

*Note : L'initialisation de certains pods lourds (comme Redpanda ou Prometheus) peut prendre 2 à 3 minutes.*

---

## ⛵ 4. Étape 3 : Déploiement GitOps (ArgoCD)

ArgoCD se synchronise automatiquement avec la branche `develop` de ce dépôt git pour déployer nos services applicatifs dans le namespace `app`.

1. **Vérifier l'état de synchronisation applicative** :
   ```bash
   # Récupérer les applications ArgoCD
   kubectl get applications -n argocd
   ```
2. **Accéder à l'interface graphique d'ArgoCD** :
   ```bash
   kubectl port-forward service/argocd-server -n argocd 8080:443
   # Ouvrir ensuite : https://localhost:8080 (Login: admin / mot de passe généré automatiquement)
   ```

---

## 🎯 5. Étape 4 : Tester l'Application en Live

Une fois les services démarrés (visibles avec `kubectl get pods -n app`) :

1. **Exposer l'interface utilisateur cartographique** (`delivery-service`) :
   ```bash
   kubectl port-forward service/delivery-service -n app 3000:3000
   ```
   *Ouvrez votre navigateur sur `http://localhost:3000` pour voir la carte Leaflet.*

2. **Créer un colis de test** :
   Exécutez cette requête POST pour ajouter un colis :
   ```bash
   curl -X POST http://localhost:3000/parcels \
     -H "Content-Type: application/json" \
     -d '{"id":"colis-demo","name":"Colis Test Cloud","recipient_email":"client@ynov.local","dest_lat":43.6107,"dest_lng":3.8767}'
   ```

3. **Vérifier les logs du simulateur** :
   Le simulateur de trajet `gps-simulator` va récupérer automatiquement le colis actif et commencer à publier des coordonnées GPS.
   ```bash
   kubectl logs -f -l app=gps-simulator -n app
   ```

4. **Superviser l'envoi de mails dans MailHog** :
   Lorsque le simulateur s'approche à moins de 500m des coordonnées de Montpellier (`43.6107, 3.8767`), `notification-service` envoie un e-mail d'alerte.
   ```bash
   kubectl port-forward service/mailhog -n mail 8025:8025
   ```
   *Ouvrez `http://localhost:8025` pour consulter la boîte de réception des alertes.*

---

## 📊 6. Étape 5 : Accéder à l'Observabilité

1. **Grafana (Monitoring et SLOs)** :
   ```bash
   kubectl port-forward service/kps-grafana -n monitoring 3000:80
   # Ouvrir : http://localhost:3000 (identifiants configurés dans le cluster)
   ```
   *Rendez-vous dans les Dashboards pour voir le tableau de bord personnalisé "GreenLogistics - Dashboard SRE" avec nos SLOs.*

2. **Kubecost (FinOps)** :
   ```bash
   kubectl port-forward service/kubecost-cost-analyzer -n kubecost 9090:9090
   # Ouvrir : http://localhost:9090
   ```

---

## 🧹 7. Étape 6 : Nettoyage en Fin de Séance

Pour libérer instantanément la mémoire RAM et les ressources de votre machine, supprimez simplement le cluster :

```bash
kind delete cluster --name greenlogistics-cluster
```
