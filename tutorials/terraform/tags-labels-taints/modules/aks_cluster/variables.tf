variable "name" {
  description = "(Required) Specifies the name of the AKS cluster."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the resource group name of the AKS cluster."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the AKS cluster."
  type        = string
}

variable "dns_prefix" {
  description = "(Optional) Specifies the DNS prefix of the AKS cluster. Empty derives it from the cluster name."
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "(Optional) Specifies the Kubernetes version. Null lets the platform pick its default."
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "(Optional) Specifies the tier of the managed cluster SKU."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "The sku tier must be Free, Standard, or Premium."
  }
}

variable "managed_identity_id" {
  description = "(Required) Specifies the resource id of the user-assigned managed identity of the AKS cluster."
  type        = string
}

variable "system_subnet_id" {
  description = "(Required) Specifies the resource id of the subnet hosting the system agent pool nodes."
  type        = string
}

variable "system_node_pool_name" {
  description = "(Optional) Specifies the name of the system agent pool."
  type        = string
  default     = "system"
}

variable "system_node_pool_vm_size" {
  description = "(Optional) Specifies the vm size of the nodes in the system agent pool."
  type        = string
  default     = "Standard_DS2_v2"
}

variable "system_node_pool_node_count" {
  description = "(Optional) Specifies the number of nodes in the system agent pool."
  type        = number
  default     = 1
}

variable "system_node_pool_auto_scaling_enabled" {
  description = "(Optional) Specifies whether to enable auto-scaling for the system agent pool."
  type        = bool
  default     = false
}

variable "system_node_pool_min_count" {
  description = "(Optional) Specifies the minimum number of nodes for auto-scaling of the system agent pool."
  type        = number
  default     = 1
}

variable "system_node_pool_max_count" {
  description = "(Optional) Specifies the maximum number of nodes for auto-scaling of the system agent pool."
  type        = number
  default     = 3
}

variable "system_node_pool_max_pods" {
  description = "(Optional) Specifies the maximum number of pods per node in the system agent pool."
  type        = number
  default     = 100
}

variable "system_node_pool_os_disk_type" {
  description = "(Optional) Specifies the OS disk type of the system agent pool."
  type        = string
  default     = "Managed"

  validation {
    condition     = contains(["Ephemeral", "Managed"], var.system_node_pool_os_disk_type)
    error_message = "The OS disk type must be Ephemeral or Managed."
  }
}

variable "system_node_pool_os_sku" {
  description = "(Optional) Specifies the OS SKU used by the system agent pool."
  type        = string
  default     = "AzureLinux"

  validation {
    condition     = contains(["Ubuntu", "AzureLinux"], var.system_node_pool_os_sku)
    error_message = "The OS SKU must be Ubuntu or AzureLinux."
  }
}

variable "system_node_pool_availability_zones" {
  description = "(Optional) Specifies the availability zones of the system agent pool. Empty deploys without zones."
  type        = list(string)
  default     = []
}

variable "system_node_pool_node_labels" {
  description = "(Optional) Specifies the node labels of the system agent pool."
  type        = map(string)
  default     = {}
}

variable "admin_username" {
  description = "(Optional) Specifies the administrator username of Linux virtual machines."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "(Optional) Specifies the SSH RSA public key for the Linux nodes. Empty omits the linux_profile (emulator-friendly)."
  type        = string
  default     = ""
}

variable "network_plugin" {
  description = "(Optional) Specifies the network plugin used for building the Kubernetes network."
  type        = string
  default     = "azure"
}

variable "network_plugin_mode" {
  description = "(Optional) Specifies the network plugin mode used for building the Kubernetes network. Empty disables overlay mode."
  type        = string
  default     = "overlay"
}

variable "network_policy" {
  description = "(Optional) Specifies the network policy used for building the Kubernetes network."
  type        = string
  default     = "azure"
}

variable "network_data_plane" {
  description = "(Optional) Specifies the network dataplane used in the Kubernetes cluster."
  type        = string
  default     = "azure"
}

variable "pod_cidr" {
  description = "(Optional) Specifies the CIDR notation IP range from which to assign pod IPs (overlay or kubenet)."
  type        = string
  default     = "192.168.0.0/16"
}

variable "service_cidr" {
  description = "(Optional) Specifies the CIDR notation IP range from which to assign service cluster IPs."
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "(Optional) Specifies the IP address assigned to the Kubernetes DNS service; must be within service_cidr."
  type        = string
  default     = "172.16.0.10"
}

variable "outbound_type" {
  description = "(Optional) Specifies the outbound (egress) routing method."
  type        = string
  default     = "loadBalancer"
}

variable "load_balancer_sku" {
  description = "(Optional) Specifies the sku of the load balancer used by the AKS cluster."
  type        = string
  default     = "standard"
}

variable "oidc_issuer_enabled" {
  description = "(Optional) Specifies whether the OIDC issuer is enabled."
  type        = bool
  default     = true
}

variable "workload_identity_enabled" {
  description = "(Optional) Specifies whether Microsoft Entra Workload ID is enabled."
  type        = bool
  default     = true
}

variable "azure_keyvault_secrets_provider_enabled" {
  description = "(Optional) Specifies whether the Azure Key Vault Provider for Secrets Store CSI Driver addon is enabled."
  type        = bool
  default     = true
}

variable "secret_rotation_enabled" {
  description = "(Optional) Specifies whether the Secrets Store CSI Driver rotates secrets."
  type        = bool
  default     = false
}

variable "keda_enabled" {
  description = "(Optional) Specifies whether the Kubernetes Event-Driven Autoscaler (KEDA) is enabled."
  type        = bool
  default     = false
}

variable "vertical_pod_autoscaler_enabled" {
  description = "(Optional) Specifies whether the Vertical Pod Autoscaler is enabled."
  type        = bool
  default     = false
}

variable "blob_csi_driver_enabled" {
  description = "(Optional) Specifies whether to enable the Azure Blob CSI Driver."
  type        = bool
  default     = true
}

variable "disk_csi_driver_enabled" {
  description = "(Optional) Specifies whether to enable the Azure Disk CSI Driver."
  type        = bool
  default     = true
}

variable "file_csi_driver_enabled" {
  description = "(Optional) Specifies whether to enable the Azure File CSI Driver."
  type        = bool
  default     = true
}

variable "snapshot_controller_enabled" {
  description = "(Optional) Specifies whether to enable the Snapshot Controller."
  type        = bool
  default     = true
}

variable "rbac_enabled" {
  description = "(Optional) Specifies whether Kubernetes Role-Based Access Control is enabled."
  type        = bool
  default     = true
}

variable "aad_enabled" {
  description = "(Optional) Specifies whether to enable managed AAD integration. When false the AAD RBAC block is omitted."
  type        = bool
  default     = true
}

variable "aad_azure_rbac_enabled" {
  description = "(Optional) Specifies whether to enable Azure RBAC for Kubernetes authorization."
  type        = bool
  default     = true
}

variable "aad_admin_group_object_ids" {
  description = "(Optional) Specifies the AAD group object IDs that will have the admin role of the cluster."
  type        = list(string)
  default     = []
}

variable "aad_tenant_id" {
  description = "(Optional) Specifies the tenant id of the Azure Active Directory used by the AKS cluster for authentication."
  type        = string
  default     = null
}

variable "automatic_upgrade_channel" {
  description = "(Optional) Specifies the upgrade channel for auto upgrade."
  type        = string
  default     = "stable"

  validation {
    condition     = contains(["rapid", "stable", "patch", "node-image", "none"], var.automatic_upgrade_channel)
    error_message = "The upgrade channel must be rapid, stable, patch, node-image, or none."
  }
}

variable "node_os_upgrade_channel" {
  description = "(Optional) Specifies the node OS upgrade channel."
  type        = string
  default     = "Unmanaged"

  validation {
    condition     = contains(["NodeImage", "None", "SecurityPatch", "Unmanaged"], var.node_os_upgrade_channel)
    error_message = "The node OS upgrade channel must be NodeImage, None, SecurityPatch, or Unmanaged."
  }
}

variable "auto_scaler_profile_scan_interval" {
  description = "(Optional) Specifies the scan interval of the auto-scaler of the AKS cluster."
  type        = string
  default     = "10s"
}

variable "auto_scaler_profile_scale_down_delay_after_add" {
  description = "(Optional) Specifies the scale down delay after add of the auto-scaler of the AKS cluster."
  type        = string
  default     = "10m"
}

variable "auto_scaler_profile_scale_down_delay_after_delete" {
  description = "(Optional) Specifies the scale down delay after delete of the auto-scaler of the AKS cluster."
  type        = string
  default     = "20s"
}

variable "auto_scaler_profile_scale_down_delay_after_failure" {
  description = "(Optional) Specifies the scale down delay after failure of the auto-scaler of the AKS cluster."
  type        = string
  default     = "3m"
}

variable "auto_scaler_profile_scale_down_unneeded" {
  description = "(Optional) Specifies the scale down unneeded time of the auto-scaler of the AKS cluster."
  type        = string
  default     = "10m"
}

variable "auto_scaler_profile_scale_down_unready" {
  description = "(Optional) Specifies the scale down unready time of the auto-scaler of the AKS cluster."
  type        = string
  default     = "20m"
}

variable "auto_scaler_profile_scale_down_utilization_threshold" {
  description = "(Optional) Specifies the utilization threshold of the auto-scaler of the AKS cluster."
  type        = string
  default     = "0.5"
}

variable "auto_scaler_profile_max_graceful_termination_sec" {
  description = "(Optional) Specifies the max graceful termination time interval in seconds for the auto-scaler of the AKS cluster."
  type        = string
  default     = "600"
}

variable "auto_scaler_profile_expander" {
  description = "(Optional) Specifies the type of node pool expander used in scale up."
  type        = string
  default     = "random"

  validation {
    condition     = contains(["least-waste", "most-pods", "priority", "random"], var.auto_scaler_profile_expander)
    error_message = "The expander must be least-waste, most-pods, priority, or random."
  }
}

variable "log_analytics_workspace_id" {
  description = "(Required) Specifies the resource id of the Log Analytics workspace."
  type        = string
}

variable "user_object_id" {
  description = "(Optional) Specifies the object id of a Microsoft Entra ID user to grant the AKS RBAC Cluster Admin role on the cluster. Empty skips the assignment."
  type        = string
  default     = ""
}

variable "tags" {
  description = "(Optional) Specifies the resource tags."
  type        = map(string)
  default     = {}
}
