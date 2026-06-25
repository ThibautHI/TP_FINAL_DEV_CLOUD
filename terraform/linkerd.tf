# ============================================================================
# Linkerd Service Mesh — CRDs + Control Plane + TLS Identity
# ============================================================================
# Linkerd nécessite des certificats TLS pour l'identité mTLS.
# On génère un CA (trust anchor) et un issuer cert via le provider TLS.
# Version pinnée à stable-2.14.10 (compatible K8s 1.30.x)
# ============================================================================

# --- Génération du Trust Anchor (CA root) ---
resource "tls_private_key" "linkerd_trust_anchor" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "linkerd_trust_anchor" {
  private_key_pem = tls_private_key.linkerd_trust_anchor.private_key_pem
  is_ca_certificate = true
  validity_period_hours = 87600 # 10 ans

  subject {
    common_name = "root.linkerd.cluster.local"
  }

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "server_auth",
    "client_auth",
  ]
}

# --- Génération de l'Issuer Certificate ---
resource "tls_private_key" "linkerd_issuer" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "linkerd_issuer" {
  private_key_pem = tls_private_key.linkerd_issuer.private_key_pem

  subject {
    common_name = "identity.linkerd.cluster.local"
  }
}

resource "tls_locally_signed_cert" "linkerd_issuer" {
  cert_request_pem      = tls_cert_request.linkerd_issuer.cert_request_pem
  ca_private_key_pem    = tls_private_key.linkerd_trust_anchor.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.linkerd_trust_anchor.cert_pem
  is_ca_certificate     = true
  validity_period_hours = 8760 # 1 an

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "server_auth",
    "client_auth",
  ]
}

# --- Linkerd CRDs (stable channel, pinned version) ---
module "helm_linkerd_crds" {
  source = "./modules/helm_deployment"

  name             = "linkerd-crds"
  repository       = "https://helm.linkerd.io/stable"
  chart            = "linkerd-crds"
  chart_version    = "1.8.0"
  namespace        = "linkerd"
  create_namespace = false
  environment      = var.environment
  team             = var.team
  timeout          = 300

  depends_on = [kubernetes_namespace_v1.namespaces]
}

# --- Linkerd Control Plane (stable channel, with TLS identity) ---
module "helm_linkerd" {
  source = "./modules/helm_deployment"

  name             = "linkerd-control-plane"
  repository       = "https://helm.linkerd.io/stable"
  chart            = "linkerd-control-plane"
  chart_version    = "1.16.11"
  namespace        = "linkerd"
  create_namespace = false
  environment      = var.environment
  team             = var.team
  timeout          = 600

  set = {
    "identityTrustAnchorsPEM" = tls_self_signed_cert.linkerd_trust_anchor.cert_pem
    "identity.issuer.tls.crtPEM" = tls_locally_signed_cert.linkerd_issuer.cert_pem
    "identity.issuer.tls.keyPEM" = tls_private_key.linkerd_issuer.private_key_pem
  }

  depends_on = [module.helm_linkerd_crds]
}
