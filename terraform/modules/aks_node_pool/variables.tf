variable "name" {
  description = "Specifies the name of the node pool."
  type        = string
  default     = "user"
}

variable "kubernetes_cluster_id" {
  description = "Specifies the resource id of the AKS cluster."
  type        = string
}

variable "subnet_id" {
  description = "Specifies the resource id of the subnet of the node pool."
  type        = string
}

variable "vm_size" {
  description = "Specifies the VM size of the nodes."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "node_count" {
  description = "Specifies the number of nodes."
  type        = number
  default     = 1
}

variable "min_count" {
  description = "Specifies the minimum number of nodes for the cluster autoscaler."
  type        = number
  default     = 1
}

variable "max_count" {
  description = "Specifies the maximum number of nodes for the cluster autoscaler."
  type        = number
  default     = 3
}

variable "max_pods" {
  description = "Specifies the maximum number of pods per node."
  type        = number
  default     = 100
}

variable "os_disk_size_gb" {
  description = "Specifies the OS disk size in GB."
  type        = number
  default     = 50
}

variable "os_disk_type" {
  description = "Specifies the OS disk type."
  type        = string
  default     = "Ephemeral"
}

variable "os_sku" {
  description = "Specifies the OS SKU."
  type        = string
  default     = "AzureLinux"
}

variable "availability_zones" {
  description = "Specifies the availability zones the nodes are spread across."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "node_labels" {
  description = "Specifies the node labels of the node pool."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Specifies the tags of the node pool."
  type        = map(string)
  default     = {}
}
