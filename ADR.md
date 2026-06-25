# Architecture Decision Records (ADR) — GreenLogistics

Ce document recense les décisions d'architecture importantes prises au cours de la conception et de la mise en œuvre de la plateforme GreenLogistics.

---

## ADR 1 : Choix d'une plateforme locale standardisée (kind)

### Statut
Accepté

### Contexte
La coupure des crédits cloud étudiants a nécessité le pivotement vers une stack locale. Il nous faut un orchestrateur conteneurisé qui permette de répliquer fidèlement un environnement Kubernetes de production (tel que Google Kubernetes Engine) tout en restant léger et reproductible sur n'importe quel ordinateur portable disposant de 12 à 16 Go de RAM.

### Décision
Nous choisissons d'utiliser **`kind`** (Kubernetes in Docker) avec un cluster à 3 nœuds (1 control-plane et 2 workers) plutôt que Minikube ou k3d. 
* *Pourquoi ?* `kind` s'intègre parfaitement avec Docker Desktop sur Windows/Mac, permet une isolation stricte des nœuds sous forme de conteneurs, et supporte nativement le port-forwarding de ports critiques (HTTP 80/443, NodePorts) sans mécanisme de tunnel complexe.

### Conséquences
* **Avantages** : Reproductibilité absolue entre les machines de l'équipe et celle du jury. Configuration IaC via le provider Terraform `tehcyx/kind`.
* **Inconvénients** : Consommation de RAM d'environ 1.5 Go rien que pour le cluster en veille.

---

## ADR 2 : Choix du Broker de Messagerie (Redpanda)

### Statut
Accepté

### Contexte
Le système requiert une communication asynchrone à haut débit entre l'ingestion des coordonnées GPS (`gps-ingest-service`) et la mise à jour des colis (`delivery-service`) ainsi que les notifications (`notification-service`).

### Décision
Nous choisissons d'utiliser **`Redpanda`** comme broker de messages compatible avec l'API Kafka.
* *Pourquoi ?* Redpanda est écrit en C++ et ne nécessite pas la JVM Java lourde de Kafka classique. Il est extrêmement économe en ressources (CPU/RAM en local) tout en offrant les performances et la durabilité de Kafka avec sa console de supervision web intégrée.

### Conséquences
* **Avantages** : Pas d'infrastructure Kafka/Zookeeper complexe à déployer. Code client compatible avec la bibliothèque Node.js `kafkajs`.
* **Inconvénients** : Légèrement plus lourd que NATS ou RabbitMQ, mais offre une gestion des logs et des offsets plus robuste pour le tracking historique.

---

## ADR 3 : Gestion des Secrets avec Vault et External Secrets Operator

### Statut
Accepté

### Contexte
Conformément aux exigences DevSecOps, aucun secret applicatif (mot de passe Postgres, jetons de connexion) ne doit être stocké en clair dans Git ou directement injecté dans les manifestes Kubernetes.

### Décision
Nous déployons **`HashiCorp Vault`** en mode dev (avec token root prévisible en local) combiné avec **`External Secrets Operator`** (ESO).
* *Pourquoi ?* Vault sert de coffre-fort de secrets dynamique. ESO agit comme un pont qui extrait les données de Vault et génère des secrets Kubernetes natifs (`api-secret`) dans le namespace applicatif, évitant ainsi d'exposer l'API Vault directement à nos applications.

### Conséquences
* **Avantages** : Découplage complet entre l'infrastructure de stockage des secrets et le runtime applicatif. Conforme aux meilleures pratiques de production (Workload Identity).
* **Inconvénients** : Processus d'initialisation post-Terraform nécessaire via un script local-exec PowerShell pour provisionner les valeurs dans Vault au démarrage.

---

## ADR 4 : Choix de la Service Mesh (Linkerd)

### Statut
Accepté

### Contexte
Le projet requiert du mTLS (Mutual TLS) automatique et transparent entre les pods du namespace applicatif, ainsi que la collecte de métriques réseau dorées.

### Décision
Nous sélectionnons **`Linkerd`** (stable-2.14) plutôt qu'Istio.
* *Pourquoi ?* Linkerd est extrêmement léger et nécessite très peu de ressources RAM (moins de 500Mo de control-plane) comparé à Istio qui est beaucoup plus lourd et complexe en local. De plus, Linkerd offre le mTLS out-of-the-box par simple annotation de namespace.

### Conséquences
* **Avantages** : Consommation de ressources optimisée. Sécurisation instantanée de toutes les liaisons inter-services sans modification du code applicatif.
* **Inconvénients** : Demande la gestion de certificats auto-signés (Trust Anchor et Issuer) via Terraform.

---

## ADR 5 : Choix de la stratégie de déploiement (Argo Rollouts Canary)

### Statut
Accepté

### Contexte
Nous devons démontrer une capacité de déploiement progressif sur l'un des services pour minimiser les risques en production.

### Décision
Nous choisissons d'installer le contrôleur **`Argo Rollouts`** et d'utiliser une ressource de type `Rollout` à la place d'un `Deployment` K8s standard pour `delivery-service`.
* *Pourquoi ?* Argo Rollouts s'intègre parfaitement avec ArgoCD et permet de définir précisément des étapes de transition (Canary) à base de poids (ex: envoyer 20% du trafic sur la nouvelle version avant validation).

### Conséquences
* **Avantages** : Visibilité graphique des déploiements. Possibilité de rollback automatique.
* **Inconvénients** : Nécessite l'installation d'un contrôleur supplémentaire dans le cluster.
