provider "helm" {
  kubernetes = {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

# deploy argo
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  values           = [file("${path.module}/../../kubernetes/platform/argocd/values.yaml")]

  depends_on = [
    google_container_cluster.primary
  ]
}

# providers
provider "kubernetes" {
  alias                  = "primary"
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

provider "kubernetes" {
  alias                  = "secondary"
  host                   = "https://${google_container_cluster.secondary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.secondary.master_auth[0].cluster_ca_certificate)
}

# target cluster rbac
resource "kubernetes_namespace_v1" "argocd_manager" {
  provider = kubernetes.secondary
  metadata {
    name = "argocd-manager"
  }
}

resource "kubernetes_service_account_v1" "argocd_manager" {
  provider = kubernetes.secondary
  metadata {
    name      = "argocd-manager"
    namespace = kubernetes_namespace_v1.argocd_manager.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding_v1" "argocd_manager" {
  provider = kubernetes.secondary
  metadata {
    name = "argocd-manager-role-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.argocd_manager.metadata[0].name
    namespace = kubernetes_namespace_v1.argocd_manager.metadata[0].name
  }
}

# long-lived token
resource "kubernetes_secret_v1" "argocd_manager_token" {
  provider = kubernetes.secondary
  metadata {
    name      = "argocd-manager-token"
    namespace = kubernetes_namespace_v1.argocd_manager.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.argocd_manager.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
}

# link em up
resource "kubernetes_secret_v1" "cluster_b_registration" {
  provider = kubernetes.primary
  metadata {
    name      = "cluster-b-secret"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
    }
  }
  data = {
    name   = "cluster-b"
    server = "https://${google_container_cluster.secondary.endpoint}"
    config = jsonencode({
      bearerToken = kubernetes_secret_v1.argocd_manager_token.data["token"]
      tlsClientConfig = {
        insecure = false
        caData   = google_container_cluster.secondary.master_auth[0].cluster_ca_certificate
      }
    })
  }

  depends_on = [helm_release.argocd]
}
