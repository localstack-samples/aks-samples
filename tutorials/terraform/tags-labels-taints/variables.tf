# --- Provider / target selection --------------------------------------------------

variable "metadata_host" {
  description = "(Optional) Specifies the Azure metadata host. Set to localhost.localstack.cloud:4566 to target the LocalStack emulator; leave null for real Azure."
  type        = string
  default     = null
}

variable "resource_manager_endpoint" {
  description = "(Optional) Specifies the Azure Resource Manager endpoint used by the azapi provider. Set to https://azure.localhost.localstack.cloud:4566/ to target the LocalStack emulator; leave null for real Azure."
  type        = string
  default     = null
}

variable "subscription_id" {
  description = "(Required) Specifies the subscription id. Real Azure requires it explicitly with azurerm 4.x; the emulator uses the all-zero GUID."
  type        = string
}

variable "tenant_id" {
  description = "(Optional) Specifies the tenant id. Only needed for the emulator (all-zero GUID); real Azure uses the Azure CLI context."
  type        = string
  default     = null
}

variable "client_id" {
  description = "(Optional) Specifies the client id of the service principal. Only needed for the emulator (all-zero GUID)."
  type        = string
  default     = null
}

variable "client_secret" {
  description = "(Optional) Specifies the client secret of the service principal. Only needed for the emulator (placeholder value)."
  type        = string
  default     = null
  sensitive   = true
}

# --- Naming ------------------------------------------------------------------------

variable "prefix" {
  description = "(Optional) Specifies the name prefix for all the Azure resources."
  type        = string
  default     = "local"

  validation {
    condition     = length(var.prefix) >= 3 && length(var.prefix) <= 10
    error_message = "The prefix must be between 3 and 10 characters."
  }
}

variable "suffix" {
  description = "(Optional) Specifies the name suffix for all the Azure resources."
  type        = string
  default     = "test"

  validation {
    condition     = length(var.suffix) >= 3 && length(var.suffix) <= 10
    error_message = "The suffix must be between 3 and 10 characters."
  }
}

variable "location" {
  description = "(Optional) Specifies the location for all the Azure resources."
  type        = string
  default     = "westeurope"
}

variable "tags" {
  description = "(Optional) Specifies the resource tags for all the Azure resources."
  type        = map(string)
  default = {
    env = "test"
    iac = "terraform"
  }
}

variable "aks_cluster_name" {
  description = "(Optional) Specifies the name of the AKS cluster. Empty derives it from prefix and suffix."
  type        = string
  default     = ""
}

variable "aks_managed_identity_name" {
  description = "(Optional) Specifies the name of the AKS user-assigned managed identity. Empty derives it from prefix and suffix."
  type        = string
  default     = ""
}

variable "virtual_network_name" {
  description = "(Optional) Specifies the name of the virtual network. Empty derives it from prefix and suffix."
  type        = string
  default     = ""
}

variable "log_analytics_workspace_name" {
  description = "(Optional) Specifies the name of the Log Analytics workspace. Empty derives it from prefix and suffix."
  type        = string
  default     = ""
}

variable "container_registry_name" {
  description = "(Optional) Specifies the name of the container registry. Empty derives it from prefix and suffix."
  type        = string
  default     = ""
}

variable "key_vault_name" {
  description = "(Optional) Specifies the name of the Key Vault. Key Vault names are globally unique; terraform.tfvars pins the real-Azure name and deploy.sh overrides it on the emulator. Empty derives it from prefix and suffix."
  type        = string
  default     = ""
}

# --- Cluster and agent pools ---------------------------------------------------------

variable "kubernetes_version" {
  description = "(Optional) Specifies the Kubernetes version. Null lets the platform pick its default."
  type        = string
  default     = null
}

variable "dns_prefix" {
  description = "(Optional) Specifies the DNS prefix of the AKS cluster. Empty derives it from the cluster name."
  type        = string
  default     = ""
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

variable "vm_size" {
  description = "(Optional) Specifies the VM size for all agent pool nodes."
  type        = string
  default     = "Standard_DS2_v2"
}

variable "system_node_pool_name" {
  description = "(Optional) Specifies the name of the system agent pool."
  type        = string
  default     = "system"
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

variable "user_node_pool_name" {
  description = "(Optional) Specifies the name of the user agent pool."
  type        = string
  default     = "upool1"
}

variable "user_node_pool_mode" {
  description = "(Optional) Specifies the mode of the user agent pool."
  type        = string
  default     = "User"

  validation {
    condition     = contains(["System", "User"], var.user_node_pool_mode)
    error_message = "The mode must be System or User."
  }
}

variable "user_node_pool_node_count" {
  description = "(Optional) Specifies the number of nodes in the user agent pool."
  type        = number
  default     = 1
}

variable "user_node_pool_auto_scaling_enabled" {
  description = "(Optional) Specifies whether to enable auto-scaling for the user agent pool."
  type        = bool
  default     = false
}

variable "user_node_pool_min_count" {
  description = "(Optional) Specifies the minimum number of nodes for auto-scaling of the user agent pool."
  type        = number
  default     = 1
}

variable "user_node_pool_max_count" {
  description = "(Optional) Specifies the maximum number of nodes for auto-scaling of the user agent pool."
  type        = number
  default     = 3
}

variable "user_node_pool_max_pods" {
  description = "(Optional) Specifies the maximum number of pods per node in the user agent pool."
  type        = number
  default     = 100
}

variable "user_node_pool_os_type" {
  description = "(Optional) Specifies the OS type of the user agent pool."
  type        = string
  default     = "Linux"

  validation {
    condition     = contains(["Linux", "Windows"], var.user_node_pool_os_type)
    error_message = "The OS type must be Linux or Windows."
  }
}

variable "user_node_pool_os_sku" {
  description = "(Optional) Specifies the OS SKU used by the user agent pool."
  type        = string
  default     = "AzureLinux"

  validation {
    condition     = contains(["Ubuntu", "AzureLinux"], var.user_node_pool_os_sku)
    error_message = "The OS SKU must be Ubuntu or AzureLinux."
  }
}

variable "user_node_pool_os_disk_type" {
  description = "(Optional) Specifies the OS disk type of the user agent pool."
  type        = string
  default     = "Managed"

  validation {
    condition     = contains(["Ephemeral", "Managed"], var.user_node_pool_os_disk_type)
    error_message = "The OS disk type must be Ephemeral or Managed."
  }
}

variable "user_node_pool_availability_zones" {
  description = "(Optional) Specifies the availability zones of the user agent pool. Empty deploys without zones."
  type        = list(string)
  default     = []
}

variable "user_node_pool_node_labels" {
  description = "(Optional) Specifies the node labels of the user agent pool."
  type        = map(string)
  default     = {}
}

variable "user_node_pool_node_taints" {
  description = "(Optional) Specifies the node taints of the user agent pool (key[=value]:effect strings)."
  type        = list(string)
  default     = []
}

variable "user_node_pool_tags" {
  description = "(Optional) Specifies the resource tags of the user agent pool."
  type        = map(string)
  default     = {}
}

variable "ssh_public_key" {
  description = "(Optional) Specifies the SSH RSA public key for the Linux nodes. Empty omits the linux_profile (emulator-friendly)."
  type        = string
  default     = ""
}

variable "admin_username" {
  description = "(Optional) Specifies the administrator username of Linux virtual machines."
  type        = string
  default     = "azureuser"
}

variable "user_object_id" {
  description = "(Optional) Specifies the object id of the deploying user, used for the AKS RBAC Cluster Admin and Key Vault Administrator role assignments. Empty skips them."
  type        = string
  default     = ""
}

# --- Networking -----------------------------------------------------------------------

variable "virtual_network_address_space" {
  description = "(Optional) Specifies the address space of the virtual network."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "system_subnet_name" {
  description = "(Optional) Specifies the name of the subnet hosting the system agent pool nodes."
  type        = string
  default     = "SystemSubnet"
}

variable "system_subnet_address_prefix" {
  description = "(Optional) Specifies the address prefix of the subnet hosting the system agent pool nodes."
  type        = string
  default     = "10.240.0.0/16"
}

variable "user_subnet_name" {
  description = "(Optional) Specifies the name of the subnet hosting the user agent pool nodes."
  type        = string
  default     = "UserSubnet"
}

variable "user_subnet_address_prefix" {
  description = "(Optional) Specifies the address prefix of the subnet hosting the user agent pool nodes."
  type        = string
  default     = "10.241.0.0/16"
}

variable "network_plugin" {
  description = "(Optional) Specifies the network plugin used for building the Kubernetes network."
  type        = string
  default     = "azure"

  validation {
    condition     = contains(["azure", "kubenet"], var.network_plugin)
    error_message = "The network plugin must be azure or kubenet."
  }
}

variable "network_plugin_mode" {
  description = "(Optional) Specifies the network plugin mode used for building the Kubernetes network. Empty disables overlay mode."
  type        = string
  default     = "overlay"

  validation {
    condition     = contains(["", "overlay"], var.network_plugin_mode)
    error_message = "The network plugin mode must be empty or overlay."
  }
}

variable "network_policy" {
  description = "(Optional) Specifies the network policy used for building the Kubernetes network."
  type        = string
  default     = "azure"

  validation {
    condition     = contains(["azure", "calico", "cilium"], var.network_policy)
    error_message = "The network policy must be azure, calico, or cilium."
  }
}

variable "network_data_plane" {
  description = "(Optional) Specifies the network dataplane used in the Kubernetes cluster."
  type        = string
  default     = "azure"

  validation {
    condition     = contains(["azure", "cilium"], var.network_data_plane)
    error_message = "The network dataplane must be azure or cilium."
  }
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

# --- Cluster features --------------------------------------------------------------------

variable "gateway_api_enabled" {
  description = "(Optional) Specifies whether to install the Managed Gateway API on the AKS cluster (applied via azapi; azurerm does not expose it yet)."
  type        = bool
  default     = true
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
  description = "(Optional) Specifies the tenant id of the Azure Active Directory used by the AKS cluster for authentication. Null uses the current tenant."
  type        = string
  default     = null
}

# --- Upgrade and auto-scaler profile ---------------------------------------------------

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

# --- Log Analytics ----------------------------------------------------------------------

variable "log_analytics_workspace_sku" {
  description = "(Optional) Specifies the service tier of the Log Analytics workspace."
  type        = string
  default     = "PerGB2018"

  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.log_analytics_workspace_sku)
    error_message = "The sku must be Free, Standalone, PerNode, or PerGB2018."
  }
}

variable "log_analytics_workspace_retention_in_days" {
  description = "(Optional) Specifies the Log Analytics workspace data retention in days."
  type        = number
  default     = 60
}

# --- Container registry -----------------------------------------------------------------

variable "container_registry_sku" {
  description = "(Optional) Specifies the tier of the container registry."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "The sku must be Basic, Standard, or Premium."
  }
}

variable "container_registry_admin_enabled" {
  description = "(Optional) Specifies whether the container registry admin user is enabled."
  type        = bool
  default     = true
}

# --- Key Vault --------------------------------------------------------------------------

variable "key_vault_sku_name" {
  description = "(Optional) Specifies the sku name of the Key Vault."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku_name)
    error_message = "The sku name must be standard or premium."
  }
}

variable "key_vault_rbac_authorization_enabled" {
  description = "(Optional) Specifies whether RBAC authorization is enabled for the Key Vault data plane."
  type        = bool
  default     = true
}

variable "key_vault_purge_protection_enabled" {
  description = "(Optional) Specifies whether purge protection is enabled. Off by default so test vaults can be purged and recreated."
  type        = bool
  default     = false
}

variable "key_vault_soft_delete_retention_days" {
  description = "(Optional) Specifies the Key Vault soft delete retention in days."
  type        = number
  default     = 7
}

variable "key_vault_public_network_access_enabled" {
  description = "(Optional) Specifies whether public network access is enabled for the Key Vault."
  type        = bool
  default     = true
}

variable "key_vault_network_acls_default_action" {
  description = "(Optional) Specifies the default action when no Key Vault network ACL rules match."
  type        = string
  default     = "Allow"

  validation {
    condition     = contains(["Allow", "Deny"], var.key_vault_network_acls_default_action)
    error_message = "The network ACLs default action must be Allow or Deny."
  }
}
