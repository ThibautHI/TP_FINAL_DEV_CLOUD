# ============================================================================
# Module: helm_deployment — Outputs
# ============================================================================

output "release_name" {
  description = "Nom de la release Helm déployée"
  value       = helm_release.this.name
}

output "release_namespace" {
  description = "Namespace de la release Helm"
  value       = helm_release.this.namespace
}

output "release_status" {
  description = "Statut de la release Helm"
  value       = helm_release.this.status
}

output "release_version" {
  description = "Version du chart déployé"
  value       = helm_release.this.version
}
