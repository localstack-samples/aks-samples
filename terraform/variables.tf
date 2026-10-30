variable "prefix" {
  description = "Specifies the prefix of every resource name, as in the scripts."
  type        = string
  default     = "local"
}

variable "suffix" {
  description = "Specifies the suffix of every resource name, as in the scripts."
  type        = string
  default     = "test"
}

variable "location" {
  description = "Specifies the location of every resource."
  type        = string
  default     = "italynorth"
}

variable "identity_type" {
  description = "Specifies the cluster identity: SystemAssigned as in scripts/01-system-assigned-managed-identity.sh, UserAssigned as in scripts/01-user-assigned-managed-identity.sh."
  type        = string
  default     = "SystemAssigned"

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned"], var.identity_type)
    error_message = "identity_type must be SystemAssigned or UserAssigned."
  }
}

variable "network_option" {
  description = "Specifies the network plugin and policy, as the scripts' menu: 1 Azure CNI Overlay with the Azure network policy, 2 with the Cilium dataplane and network policy, 3 with the Calico network policy."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 2, 3], var.network_option)
    error_message = "network_option must be 1, 2 or 3."
  }
}

variable "kubernetes_version" {
  description = "Specifies the Kubernetes version. null lets AKS pick its default; deploy.sh passes the latest GA version in the region, as the scripts do."
  type        = string
  default     = null
}

variable "system_node_count" {
  description = "Specifies the number of nodes of the system node pool. The autoscaler range, 1 to 3, is widened to include it."
  type        = number
  default     = 1
}

variable "user_node_count" {
  description = "Specifies the number of nodes of the user node pool. The autoscaler range, 1 to 3, is widened to include it."
  type        = number
  default     = 1
}

variable "node_vm_size" {
  description = "Specifies the VM size of the nodes of both node pools."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "os_sku" {
  description = "Specifies the OS SKU of the nodes."
  type        = string
  default     = "AzureLinux"
}

variable "os_disk_size_gb" {
  description = "Specifies the OS disk size in GB of the nodes."
  type        = number
  default     = 50
}

variable "os_disk_type" {
  description = "Specifies the OS disk type of the nodes."
  type        = string
  default     = "Ephemeral"
}

variable "max_pods" {
  description = "Specifies the maximum number of pods per node."
  type        = number
  default     = 100
}

variable "ssh_public_key" {
  description = "Specifies the SSH public key of the Linux nodes. On Azure, deploy.sh reads ~/.ssh/id_rsa.pub, as the scripts do."
  type        = string
  default     = ""
}

variable "windows_admin_username" {
  description = "Specifies the administrator user name of Windows nodes."
  type        = string
  default     = "azadmin"
}

variable "windows_admin_password" {
  description = "Specifies the administrator password of Windows nodes. deploy.sh passes it as TF_VAR_windows_admin_password."
  type        = string
  sensitive   = true
}

variable "aad_admin_group_object_ids" {
  description = "Specifies the object ids of the Microsoft Entra ID groups that administer the cluster. On Azure, pass real group object ids."
  type        = list(string)
  default     = []
}

variable "acr_sku" {
  description = "Specifies the SKU of the container registry."
  type        = string
  default     = "Basic"
}

variable "log_analytics_sku" {
  description = "Specifies the pricing tier of the Log Analytics workspace."
  type        = string
  default     = "PerGB2018"
}

variable "diagnostic_settings_name" {
  description = "Specifies the name of the diagnostic settings of every resource."
  type        = string
  default     = "default"
}

variable "gateway_api_enabled" {
  description = "Specifies whether to install the managed Gateway API CRDs with azapi. deploy.sh passes false on the emulator."
  type        = bool
  default     = true
}

# Provider settings: null targets Azure with the Azure CLI credentials; deploy.sh passes the LocalStack values when
# the Azure CLI targets the emulator
variable "metadata_host" {
  description = "Specifies the metadata host of the azurerm provider (the emulator's, or null for Azure)."
  type        = string
  default     = null
}

variable "resource_manager_endpoint" {
  description = "Specifies the Resource Manager endpoint of the azapi provider (the emulator's, or null for Azure)."
  type        = string
  default     = null
}

variable "subscription_id" {
  description = "Specifies the subscription id."
  type        = string
  default     = null
}

variable "tenant_id" {
  description = "Specifies the tenant id."
  type        = string
  default     = null
}

variable "client_id" {
  description = "Specifies the client id (the emulator's placeholder, or null for the Azure CLI credentials)."
  type        = string
  default     = null
}

variable "client_secret" {
  description = "Specifies the client secret (the emulator's placeholder, or null for the Azure CLI credentials)."
  type        = string
  default     = null
  sensitive   = true
}
