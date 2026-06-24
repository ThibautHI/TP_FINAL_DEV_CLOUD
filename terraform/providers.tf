# ============================================================================
# Terraform Providers — GreenLogistics
# ============================================================================
# Providers requis (exigence 4.3 du sujet) :
#   - tehcyx/kind       → Provisionnement du cluster Kubernetes local
#   - hashicorp/kubernetes → Gestion des namespaces et ressources K8s
#   - hashicorp/helm       → Déploiement des charts Helm
#   - hashicorp/null       → Scripts post-provisionnement (Vault, External Secrets)
# ============================================================================

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.7"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# --- Provider kind ---
provider "kind" {}

# --- Provider Kubernetes ---
# Pointe sur le kubeconfig généré par le cluster kind
provider "kubernetes" {
  host                   = kind_cluster.greenlogistics.endpoint
  cluster_ca_certificate = kind_cluster.greenlogistics.cluster_ca_certificate
  client_certificate     = kind_cluster.greenlogistics.client_certificate
  client_key             = kind_cluster.greenlogistics.client_key
}

# --- Provider Helm ---
# Utilise les mêmes credentials que le provider Kubernetes
provider "helm" {
  kubernetes {
    host                   = kind_cluster.greenlogistics.endpoint
    cluster_ca_certificate = kind_cluster.greenlogistics.cluster_ca_certificate
    client_certificate     = kind_cluster.greenlogistics.client_certificate
    client_key             = kind_cluster.greenlogistics.client_key
  }
}
