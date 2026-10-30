variable "name" {
  description = "Specifies the name of the key vault."
  type        = string
}

variable "location" {
  description = "Specifies the location of the key vault."
  type        = string
}

variable "resource_group_name" {
  description = "Specifies the name of the resource group."
  type        = string
}

variable "tenant_id" {
  description = "Specifies the tenant id of the key vault."
  type        = string
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
