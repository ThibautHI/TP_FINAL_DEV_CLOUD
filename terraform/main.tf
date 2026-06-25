# ============================================================================
# Main — GreenLogistics Infrastructure-as-Code
# ============================================================================
# Ordre de déploiement :
#   1. Cluster kind (3 nodes)
#   2. Namespaces Kubernetes
#   3. Briques de plateforme (Helm charts via module helm_deployment)
#   4. Services applicatifs (déployés via ArgoCD ou manifestes K8s)
# ============================================================================

# ============================================================================
# 1. CLUSTER KIND — 1 control-plane + 2 workers
# ============================================================================
resource "kind_cluster" "greenlogistics" {
  name           = var.cluster_name
  node_image     = "kindest/node:${var.k8s_version}"
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # Port mappings pour accéder aux services depuis l'hôte
      extra_port_mappings {
        container_port = 80
        host_port      = 80
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 443
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30080
        host_port      = 30080
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30090
        host_port      = 30090
        protocol       = "TCP"
      }
    }

    node {
      role = "worker"
    }

    node {
      role = "worker"
    }
  }
}

# ============================================================================
# 2. NAMESPACES KUBERNETES
# ============================================================================
locals {
  namespaces = [
    "app",
    "db",
    "messaging",
    "monitoring",
    "vault",
    "external-secrets",
    "argocd",
    "ingress-nginx",
    "cert-manager",
    "linkerd",
    "kubecost",
    "mail",
    "argo-rollouts",
  ]
}

resource "kubernetes_namespace_v1" "namespaces" {
  for_each = toset(local.namespaces)

  metadata {
    name = each.value

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "team"                         = var.team
      "env"                          = var.environment
    }
  }

  depends_on = [kind_cluster.greenlogistics]
}

# ============================================================================
# 3. BRIQUES DE PLATEFORME — Déploiements Helm via module maison
# ============================================================================

# --- 3.1 Ingress NGINX ---
module "helm_ingress_nginx" {
  source = "./modules/helm_deployment"

  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = false
  environment      = var.environment
  team             = var.team
  timeout          = 300

  set = {
    "controller.hostPort.enabled"  = "true"
    "controller.service.type"      = "NodePort"
    "controller.watchIngressWithoutClass" = "true"
  }

  depends_on = [kubernetes_namespace_v1.namespaces]
}

# --- 3.2 cert-manager ---
module "helm_cert_manager" {
  source = "./modules/helm_deployment"

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = false
  environment      = var.environment
  team             = var.team
  timeout          = 300

  set = {
    "crds.enabled" = "true"
  }

  depends_on = [kubernetes_namespace_v1.namespaces]
}

# --- 3.3 ArgoCD ---
module "helm_argocd" {
  source = "./modules/helm_deployment"

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = false
  environment      = var.environment
  team             = var.team
  timeout          = 600

  set = {
    "server.service.type"          = "NodePort"
    "server.service.nodePortHttp"  = "30080"
    "configs.params.server\\.insecure" = "true"
    "configs.secret.argocdServerAdminPassword" = "$$2a$$10$$WWBJNyYw2XaKeVKbAG0MnuProSDp7ZVX6hpaw3.UWsfesTG0uKJkS"
  }

  depends_on = [kubernetes_namespace_v1.namespaces]
}

# --- 3.4 kube-prometheus-stack (Prometheus + Grafana + Alertmanager) ---
module "helm_kps" {
  source = "./modules/helm_deployment"

  name             = "kps"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = false
  environment      = var.environment
  team             = var.team
  timeout          = 600

  set = {
    "grafana.service.type"                            = "NodePort"
    "grafana.service.nodePort"                        = "30090"
    "grafana.adminPassword"                           = "admin"
    "prometheus.prometheusSpec.retention"              = "2d"
    "prometheus.prometheusSpec.resources.requests.memory" = "512Mi"
    "prometheus.prometheusSpec.resources.limits.memory"   = "1Gi"
  }

  depends_on = [kubernetes_namespace_v1.namespaces]
}

# --- 3.5 Loki (logs centralisés) ---
module "helm_loki" {
  source = "./modules/helm_deployment"

  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  namespace        = "monitoring"
  create_namespace = false
  environment      = var.environment
  team             = var.team
  timeout          = 600
  wait             = false

  set = {
    "deploymentMode"                    = "SingleBinary"
    "loki.commonConfig.replication_factor" = "1"
    "loki.storage.type"                 = "filesystem"
    "singleBinary.replicas"             = "1"
    "loki.schemaConfig.configs[0].from"       = "2024-01-01"
    "loki.schemaConfig.configs[0].store"      = "tsdb"
    "loki.schemaConfig.configs[0].object_store" = "filesystem"
    "loki.schemaConfig.configs[0].schema"     = "v13"
    "loki.schemaConfig.configs[0].index.prefix" = "index_"
    "loki.schemaConfig.configs[0].index.period" = "24h"
    "read.replicas"                     = "0"
    "write.replicas"                    = "0"
    "backend.replicas"                  = "0"
  }

  depends_on = [module.helm_kps]
}

# --- 3.6 Promtail ---
module "helm_promtail" {
  source = "./modules/helm_deployment"

  name             = "promtail"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "promtail"
  namespace        = "monitoring"
  create_namespace = false
  environment      = var.environment
  team             = var.team
  timeout          = 300

  set = {
    "config.clients[0].url" = "http://loki:3100/loki/api/v1/push"
  }

  depends_on = [module.helm_loki]
}

# --- 3.7 HashiCorp Vault (dev-mode) ---
module "helm_vault" {
  source = "./modules/helm_deployment"

  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  namespace        = "vault"
  create_namespace = false
  environment      = var.environment
  team             = var.team
  timeout          = 300

  set = {
    "server.dev.enabled"      = "true"
    "server.dev.devRootToken"  = "root"
  }

  depends_on = [kubernetes_namespace_v1.namespaces]
}

# --- 3.8 External Secrets Operator ---
module "helm_external_secrets" {
  source = "./modules/helm_deployment"

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = false
  environment      = var.environment
  team             = var.team
  timeout          = 300

  set = {
    "installCRDs" = "true"
  }

  depends_on = [kubernetes_namespace_v1.namespaces]
}

# --- 3.9 PostgreSQL (Bitnami) ---
module "helm_postgres" {
  source = "./modules/helm_deployment"

  name             = "postgres"
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "postgresql"
  namespace        = "db"
  create_namespace = false
  environment      = var.environment
  team             = var.team
  timeout          = 600

  set = {
    "auth.username"            = "postgres"
    "auth.password"            = "postgres"
    "auth.database"            = "greenlogistics"
    "primary.persistence.size" = "1Gi"
  }

  depends_on = [kubernetes_namespace_v1.namespaces]
}

# --- 3.10 Redpanda (messaging Kafka-compatible) ---
module "helm_redpanda" {
  source = "./modules/helm_deployment"

  name             = "redpanda"
  repository       = "https://charts.redpanda.com"
  chart            = "redpanda"
  namespace        = "messaging"
  create_namespace = false
  environment      = var.environment
  team             = var.team
  timeout          = 600

  set = {
    "statefulset.replicas"           = "1"
    "resources.cpu.cores"            = "0.5"
    "resources.memory.container.max" = "2Gi"
    "tls.enabled"                    = "false"
    "external.enabled"               = "false"
    "console.enabled"                = "false"
  }

  depends_on = [kubernetes_namespace_v1.namespaces]
}

# --- 3.11 Linkerd — voir linkerd.tf ---

# --- 3.12 Kubecost ---
module "helm_kubecost" {
  source = "./modules/helm_deployment"

  name             = "kubecost"
  repository       = "https://kubecost.github.io/cost-analyzer/"
  chart            = "cost-analyzer"
  chart_version    = "2.8.6"
  namespace        = "kubecost"
  create_namespace = false
  environment      = var.environment
  team             = var.team
  timeout          = 600
  wait             = false

  set = {
    "kubecostToken"                         = "aGVsbS1jaGFydEBrdWJlY29zdC5jb20=xm343yadf98"
    "prometheus.kube-state-metrics.disabled" = "true"
    "prometheus.nodeExporter.enabled"        = "false"
    "global.clusterId"                       = var.cluster_name
  }

  depends_on = [module.helm_kps]
}

# --- 3.13 Argo Rollouts (Canary deployments operator) ---
module "helm_argo_rollouts" {
  source = "./modules/helm_deployment"

  name             = "argo-rollouts"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-rollouts"
  namespace        = "argo-rollouts"
  create_namespace = false
  environment      = var.environment
  team             = var.team
  timeout          = 300

  set = {
    "dashboard.enabled" = "false" # non requis localement, CLI suffit
  }

  depends_on = [kubernetes_namespace_v1.namespaces]
}

# ============================================================================
# 4. MAILHOG — Déploiement K8s natif (pas de chart Helm)
# ============================================================================
resource "kubernetes_deployment_v1" "mailhog" {
  metadata {
    name      = "mailhog"
    namespace = "mail"

    labels = {
      app  = "mailhog"
      team = var.team
      env  = var.environment
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "mailhog"
      }
    }

    template {
      metadata {
        labels = {
          app  = "mailhog"
          team = var.team
          env  = var.environment
        }
      }

      spec {
        container {
          name  = "mailhog"
          image = "mailhog/mailhog:latest"

          port {
            container_port = 1025
            name           = "smtp"
          }

          port {
            container_port = 8025
            name           = "http"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.namespaces]
}

resource "kubernetes_service_v1" "mailhog" {
  metadata {
    name      = "mailhog"
    namespace = "mail"

    labels = {
      app  = "mailhog"
      team = var.team
      env  = var.environment
    }
  }

  spec {
    selector = {
      app = "mailhog"
    }

    port {
      name        = "smtp"
      port        = 1025
      target_port = 1025
    }

    port {
      name        = "http"
      port        = 8025
      target_port = 8025
    }
  }

  depends_on = [kubernetes_namespace_v1.namespaces]
}
