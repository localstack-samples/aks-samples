variable "name" {
  description = "(Required) Specifies the name of the agent pool."
  type        = string
}

variable "kubernetes_cluster_id" {
  description = "(Required) Specifies the resource id of the AKS cluster."
  type        = string
}

variable "mode" {
  description = "(Optional) Specifies the mode of the agent pool."
  type        = string
  default     = "User"

  validation {
    condition     = contains(["System", "User"], var.mode)
    error_message = "The mode must be System or User."
  }
}

variable "vm_size" {
  description = "(Optional) Specifies the vm size of the nodes in the agent pool."
  type        = string
  default     = "Standard_DS2_v2"
}

variable "subnet_id" {
  description = "(Required) Specifies the resource id of the subnet hosting the agent pool nodes."
  type        = string
}

variable "node_count" {
  description = "(Optional) Specifies the number of nodes in the agent pool."
  type        = number
  default     = 1
}

variable "auto_scaling_enabled" {
  description = "(Optional) Specifies whether to enable auto-scaling for the agent pool."
  type        = bool
  default     = false
}

variable "min_count" {
  description = "(Optional) Specifies the minimum number of nodes for auto-scaling of the agent pool."
  type        = number
  default     = 1
}

variable "max_count" {
  description = "(Optional) Specifies the maximum number of nodes for auto-scaling of the agent pool."
  type        = number
  default     = 3
}

variable "max_pods" {
  description = "(Optional) Specifies the maximum number of pods per node in the agent pool."
  type        = number
  default     = 100
}

variable "os_type" {
  description = "(Optional) Specifies the OS type of the agent pool."
  type        = string
  default     = "Linux"

  validation {
    condition     = contains(["Linux", "Windows"], var.os_type)
    error_message = "The OS type must be Linux or Windows."
  }
}

variable "os_sku" {
  description = "(Optional) Specifies the OS SKU used by the agent pool."
  type        = string
  default     = "AzureLinux"

  validation {
    condition     = contains(["Ubuntu", "AzureLinux"], var.os_sku)
    error_message = "The OS SKU must be Ubuntu or AzureLinux."
  }
}

variable "os_disk_type" {
  description = "(Optional) Specifies the OS disk type of the agent pool."
  type        = string
  default     = "Managed"

  validation {
    condition     = contains(["Ephemeral", "Managed"], var.os_disk_type)
    error_message = "The OS disk type must be Ephemeral or Managed."
  }
}

variable "availability_zones" {
  description = "(Optional) Specifies the availability zones of the agent pool. Empty deploys without zones."
  type        = list(string)
  default     = []
}

variable "node_labels" {
  description = "(Optional) Specifies the node labels of the agent pool."
  type        = map(string)
  default     = {}
}

variable "node_taints" {
  description = "(Optional) Specifies the node taints of the agent pool (key[=value]:effect strings)."
  type        = list(string)
  default     = []
}

variable "node_pool_tags" {
  description = "(Optional) Specifies the resource tags persisted on the agent pool virtual machine scale set."
  type        = map(string)
  default     = {}
}
