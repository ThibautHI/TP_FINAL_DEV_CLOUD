# ============================================================================
# Module: helm_deployment
# Description: Module Terraform réutilisable pour déployer des charts Helm
#              avec des labels FinOps standardisés (team, env, app).
# ============================================================================

variable "name" {
  description = "Nom de la release Helm"
  type        = string
}

variable "repository" {
  description = "URL du repository Helm"
  type        = string
}

variable "chart" {
  description = "Nom du chart Helm"
  type        = string
}

variable "chart_version" {
  description = "Version du chart Helm (laisser vide pour la dernière version)"
  type        = string
  default     = null
}

variable "namespace" {
  description = "Namespace Kubernetes cible"
  type        = string
}

variable "create_namespace" {
  description = "Créer le namespace s'il n'existe pas"
  type        = bool
  default     = false
}

variable "values" {
  description = "Liste de fichiers YAML de values à passer au chart"
  type        = list(string)
  default     = []
}

variable "set" {
  description = "Map de valeurs individuelles à passer au chart (clé = chemin, valeur = valeur)"
  type        = map(string)
  default     = {}
}

variable "set_sensitive" {
  description = "Map de valeurs sensibles à passer au chart"
  type        = map(string)
  default     = {}
}

variable "timeout" {
  description = "Timeout en secondes pour le déploiement Helm"
  type        = number
  default     = 600
}

variable "wait" {
  description = "Attendre que toutes les ressources soient prêtes"
  type        = bool
  default     = true
}

variable "atomic" {
  description = "Rollback automatique en cas d'échec"
  type        = bool
  default     = false
}

variable "environment" {
  description = "Environnement de déploiement (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "team" {
  description = "Nom de l'équipe propriétaire (label FinOps)"
  type        = string
  default     = "greenlogistics"
}
