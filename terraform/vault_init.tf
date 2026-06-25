# ============================================================================
# Post-provisionnement — Vault init + External Secrets setup
# ============================================================================
# Ce fichier gère la configuration post-installation de Vault et
# l'application des manifestes External Secrets (ClusterSecretStore +
# ExternalSecret) une fois que les CRDs sont installées.
# ============================================================================

# --- Initialisation de Vault + External Secrets ---
resource "null_resource" "vault_init" {
  # Re-exécuter si Vault ou External Secrets changent
  triggers = {
    vault_release     = module.helm_vault.release_name
    es_release        = module.helm_external_secrets.release_name
  }

  provisioner "local-exec" {
    interpreter = ["powershell", "-Command"]
    command     = <<-EOT
      $env:Path = "C:\kubernetes;" + $env:Path

      Write-Host "=== Attente que Vault soit ready ==="
      kubectl wait --for=condition=ready pod/vault-0 -n vault --timeout=120s

      Write-Host "=== Provisionnement des secrets dans Vault ==="
      kubectl -n vault exec vault-0 -- vault kv put secret/api `
        db_password=postgres `
        db_host="postgres-postgresql.db.svc.cluster.local" `
        db_user=postgres `
        db_name=greenlogistics `
        kafka_broker="redpanda.messaging.svc.cluster.local:9093" `
        smtp_host="mailhog.mail.svc.cluster.local" `
        smtp_port=1025

      Write-Host "=== Création du token Vault pour External Secrets ==="
      kubectl -n external-secrets create secret generic vault-token --from-literal=token=root --dry-run=client -o yaml | kubectl apply -f -

      Write-Host "=== Attente des CRDs External Secrets ==="
      $maxRetries = 12
      $retryCount = 0
      $success = $false

      while (-not $success -and $retryCount -lt $maxRetries) {
        $retryCount++
        Write-Host "Tentative d'application external-secrets-setup.yaml ($retryCount/$maxRetries)..."
        try {
          kubectl apply -f "./manifests/external-secrets-setup.yaml" 2>&1
          if ($LASTEXITCODE -eq 0) {
            $success = $true
            Write-Host "External Secrets configuré avec succès !"
          } else {
            Write-Host "Échec, nouvelle tentative dans 10s..."
            Start-Sleep -Seconds 10
          }
        } catch {
          Write-Host "Erreur: $_. Nouvelle tentative dans 10s..."
          Start-Sleep -Seconds 10
        }
      }

      if (-not $success) {
        throw "Impossible d'appliquer external-secrets-setup.yaml après $maxRetries tentatives."
      }
    EOT
  }

  depends_on = [
    module.helm_vault,
    module.helm_external_secrets,
    module.helm_postgres,
    module.helm_redpanda,
    kubernetes_deployment_v1.mailhog,
  ]
}
