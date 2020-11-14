locals {
  base_domain                       = format("%s.nip.io", replace(module.cluster.ingress_ip_address, ".", "-"))
  context                           = yamldecode(module.cluster.kubeconfig)
  kubernetes_host                   = local.context.clusters.0.cluster.server
  kubernetes_username               = local.context.users.0.user.username
  kubernetes_password               = local.context.users.0.user.password
  kubernetes_cluster_ca_certificate = base64decode(local.context.clusters.0.cluster.certificate-authority-data)
}

provider "helm" {
  kubernetes {
    insecure         = true
    host             = local.kubernetes_host
    username         = local.kubernetes_username
    password         = local.kubernetes_password
    load_config_file = false
  }
}

module "cluster" {
  source  = "camptocamp/k3s/docker"
  version = "0.3.2"

  cluster_name = var.cluster_name
  k3s_version  = var.k3s_version
  node_count   = var.node_count
}

resource "helm_release" "argocd" {
  name              = "argocd"
  chart             = "${path.module}/../../argocd/argocd"
  namespace         = "argocd"
  dependency_update = true
  create_namespace  = true

  values = [
    file("${path.module}/../../argocd/argocd/values.yaml")
  ]

  depends_on = [
    module.cluster,
  ]
}

resource "helm_release" "app_of_apps" {
  name              = "app-of-apps"
  chart             = "${path.module}/../../argocd/app-of-apps"
  namespace         = "argocd"
  dependency_update = true
  create_namespace  = true

  values = [
    templatefile("${path.module}/values.tmpl.yaml",
      {
        cluster_name    = var.cluster_name,
        base_domain     = local.base_domain,
        repo_url        = var.repo_url,
        target_revision = var.target_revision,
      }
    ),
    var.app_of_apps_values_overrides,
  ]

  depends_on = [
    helm_release.argocd,
  ]
}
