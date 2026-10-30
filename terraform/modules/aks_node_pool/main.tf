# User node pool of the AKS cluster, as the cluster scripts add it with az aks nodepool add
resource "azurerm_kubernetes_cluster_node_pool" "node_pool" {
  name                  = var.name
  kubernetes_cluster_id = var.kubernetes_cluster_id
  mode                  = "User"
  vm_size               = var.vm_size
  vnet_subnet_id        = var.subnet_id
  node_count            = var.node_count
  auto_scaling_enabled  = true
  min_count             = var.min_count
  max_count             = var.max_count
  max_pods              = var.max_pods
  os_type               = "Linux"
  os_sku                = var.os_sku
  os_disk_size_gb       = var.os_disk_size_gb
  os_disk_type          = var.os_disk_type
  zones                 = var.availability_zones
  node_labels           = var.node_labels
  tags                  = var.tags

  upgrade_settings {
    max_surge = "10%"
  }

  lifecycle {
    # The cluster autoscaler changes the node count
    ignore_changes = [node_count]
  }
}
