# ============================================================================
# Module: helm_deployment
# Ressource principale: helm_release avec labels FinOps standardisés
# ============================================================================

resource "helm_release" "this" {
  name             = var.name
  repository       = var.repository
  chart            = var.chart
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  timeout          = var.timeout
  wait             = var.wait
  atomic           = var.atomic

  # Fichiers de values YAML
  dynamic "set" {
    for_each = var.set
    content {
      name  = set.key
      value = set.value
    }
  }

  dynamic "set_sensitive" {
    for_each = var.set_sensitive
    content {
      name  = set_sensitive.key
      value = set_sensitive.value
    }
  }

  values = var.values
}
