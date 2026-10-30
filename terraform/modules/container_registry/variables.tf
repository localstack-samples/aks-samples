variable "name" {
  description = "Specifies the name of the container registry."
  type        = string
}

variable "location" {
  description = "Specifies the location of the container registry."
  type        = string
}

variable "resource_group_name" {
  description = "Specifies the name of the resource group."
  type        = string
}

variable "sku" {
  description = "Specifies the SKU of the container registry."
  type        = string
  default     = "Basic"
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
