# ============================================================================
# Outputs — GreenLogistics Terraform
# ============================================================================

output "cluster_name" {
  description = "Nom du cluster kind"
  value       = kind_cluster.greenlogistics.name
}

output "cluster_endpoint" {
  description = "Endpoint de l'API server Kubernetes"
  value       = kind_cluster.greenlogistics.endpoint
}

output "kubeconfig" {
  description = "Kubeconfig du cluster (sensible)"
  value       = kind_cluster.greenlogistics.kubeconfig
  sensitive   = true
}

# --- URLs d'accès aux services ---
output "argocd_url" {
  description = "URL de l'UI ArgoCD"
  value       = "https://localhost:30080"
}

output "grafana_url" {
  description = "URL de l'UI Grafana"
  value       = "http://localhost:30090"
}

output "mailhog_url" {
  description = "URL de l'UI MailHog (nécessite port-forward : kubectl -n mail port-forward svc/mailhog 8025:8025)"
  value       = "http://localhost:8025 (après port-forward)"
}

# --- Images GHCR ---
output "ghcr_images" {
  description = "URLs des images Docker publiées sur GHCR"
  value = {
    for service in var.services :
    service => "ghcr.io/${var.github_owner}/${var.github_repo}/${service}:${var.image_tag}"
  }
}

# --- Commande pour puller les images depuis un autre projet ---
output "docker_pull_commands" {
  description = "Commandes Docker pour puller les images depuis un autre projet"
  value = join("\n", [
    for service in var.services :
    "docker pull ghcr.io/${var.github_owner}/${var.github_repo}/${service}:${var.image_tag}"
  ])
}
