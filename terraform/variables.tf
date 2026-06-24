# ============================================================================
# Variables globales — GreenLogistics Terraform
# ============================================================================

variable "cluster_name" {
  description = "Nom du cluster kind"
  type        = string
  default     = "greenlogistics-cluster"
}

variable "k8s_version" {
  description = "Version de l'image Kubernetes pour les nodes kind"
  type        = string
  default     = "v1.30.2"
}

variable "github_owner" {
  description = "Propriétaire GitHub (pour les images GHCR)"
  type        = string
  default     = "thibauthi"
}

variable "github_repo" {
  description = "Nom du dépôt GitHub (en minuscules)"
  type        = string
  default     = "tp_final_dev_cloud"
}

variable "environment" {
  description = "Environnement de déploiement"
  type        = string
  default     = "dev"
}

variable "team" {
  description = "Nom de l'équipe (label FinOps)"
  type        = string
  default     = "greenlogistics"
}

# --- Services applicatifs ---
variable "services" {
  description = "Liste des microservices à déployer"
  type        = list(string)
  default = [
    "delivery-service",
    "gps-ingest-service",
    "notification-service",
    "gps-simulator"
  ]
}

variable "image_tag" {
  description = "Tag des images Docker à déployer (par défaut: latest)"
  type        = string
  default     = "latest"
}
