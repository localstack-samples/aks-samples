# User agent pool of the AKS cluster, on UserSubnet, carrying the sample's node
# labels, node taints, and agent-pool tags (the tags/labels/taints focus of this
# sample lives here and on the cluster). No lifecycle ignore_changes on tags here:
# tags/labels/taints are the properties under test and drift must surface.

resource "azurerm_kubernetes_cluster_node_pool" "node_pool" {
  name                  = var.name
  kubernetes_cluster_id = var.kubernetes_cluster_id
  mode                  = var.mode
  vm_size               = var.vm_size
  vnet_subnet_id        = var.subnet_id
  node_count            = var.node_count
  auto_scaling_enabled  = var.auto_scaling_enabled
  min_count             = var.auto_scaling_enabled ? var.min_count : null
  max_count             = var.auto_scaling_enabled ? var.max_count : null
  max_pods              = var.max_pods
  os_type               = var.os_type
  os_sku                = var.os_sku
  os_disk_type          = var.os_disk_type
  zones                 = length(var.availability_zones) > 0 ? var.availability_zones : null
  node_labels           = var.node_labels
  node_taints           = var.node_taints
  tags                  = var.node_pool_tags

  # Matches the value AKS assigns automatically; leaving it unset makes every
  # real-Azure plan carry a perpetual in-place diff.
  upgrade_settings {
    max_surge = "10%"
  }
}
