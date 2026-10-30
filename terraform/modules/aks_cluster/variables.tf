variable "name" {
  description = "Specifies the name of the AKS cluster."
  type        = string
}

variable "location" {
  description = "Specifies the location of the AKS cluster."
  type        = string
}

variable "resource_group_name" {
  description = "Specifies the name of the resource group."
  type        = string
}

variable "subscription_id" {
  description = "Specifies the subscription id, which the DNS prefix includes as az aks create does."
  type        = string
}

variable "tenant_id" {
  description = "Specifies the tenant id of Microsoft Entra ID."
  type        = string
}

variable "tags" {
  description = "Specifies the tags of the AKS cluster."
  type        = map(string)
  default     = {}
}

variable "kubernetes_version" {
  description = "Specifies the Kubernetes version. null lets AKS pick its default."
  type        = string
  default     = null
}

variable "identity_type" {
  description = "Specifies the type of the cluster identity: SystemAssigned or UserAssigned."
  type        = string
  default     = "SystemAssigned"
}

variable "user_assigned_identity_id" {
  description = "Specifies the resource id of the user-assigned identity of the cluster, when identity_type is UserAssigned."
  type        = string
  default     = ""
}

variable "system_node_pool_name" {
  description = "Specifies the name of the system node pool."
  type        = string
  default     = "system"
}

variable "system_subnet_id" {
  description = "Specifies the resource id of the subnet of the system node pool."
  type        = string
}

variable "vm_size" {
  description = "Specifies the VM size of the system node pool."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "node_count" {
  description = "Specifies the number of nodes of the system node pool."
  type        = number
  default     = 1
}

variable "min_count" {
  description = "Specifies the minimum number of nodes of the system node pool for the cluster autoscaler."
  type        = number
  default     = 1
}

variable "max_count" {
  description = "Specifies the maximum number of nodes of the system node pool for the cluster autoscaler."
  type        = number
  default     = 3
}

variable "max_pods" {
  description = "Specifies the maximum number of pods per node of the system node pool."
  type        = number
  default     = 100
}

variable "os_disk_size_gb" {
  description = "Specifies the OS disk size in GB of the system node pool."
  type        = number
  default     = 50
}

variable "os_disk_type" {
  description = "Specifies the OS disk type of the system node pool."
  type        = string
  default     = "Ephemeral"
}

variable "os_sku" {
  description = "Specifies the OS SKU of the system node pool."
  type        = string
  default     = "AzureLinux"
}

variable "node_labels" {
  description = "Specifies the node labels of the system node pool."
  type        = map(string)
  default     = {}
}

variable "node_pool_tags" {
  description = "Specifies the tags of the system node pool."
  type        = map(string)
  default     = {}
}

variable "linux_admin_username" {
  description = "Specifies the administrator user name of the Linux nodes."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "Specifies the SSH public key of the Linux nodes. Empty omits the Linux profile."
  type        = string
  default     = ""
}

variable "windows_admin_username" {
  description = "Specifies the administrator user name of Windows nodes."
  type        = string
  default     = "azadmin"
}

variable "windows_admin_password" {
  description = "Specifies the administrator password of Windows nodes."
  type        = string
  sensitive   = true
}

variable "network_policy" {
  description = "Specifies the network policy: azure, calico or cilium."
  type        = string
  default     = "azure"
}

variable "network_data_plane" {
  description = "Specifies the network dataplane: azure or cilium."
  type        = string
  default     = "azure"
}

variable "pod_cidr" {
  description = "Specifies the CIDR of the pods."
  type        = string
  default     = "192.168.0.0/16"
}

variable "service_cidr" {
  description = "Specifies the CIDR of the services."
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "Specifies the IP address of the Kubernetes DNS service, within service_cidr."
  type        = string
  default     = "172.16.0.10"
}

variable "aad_admin_group_object_ids" {
  description = "Specifies the object ids of the Microsoft Entra ID groups that administer the cluster."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Specifies the resource id of the Log Analytics workspace."
  type        = string
}

variable "diagnostic_settings_name" {
  description = "Specifies the name of the diagnostic settings."
  type        = string
  default     = "default"
}
