variable "name" {
  description = "(Required) Specifies the name of the container registry (alphanumeric only, globally unique)."
  type        = string

  validation {
    condition     = length(var.name) >= 5 && length(var.name) <= 50
    error_message = "The container registry name must be between 5 and 50 characters."
  }
}

variable "resource_group_name" {
  description = "(Required) Specifies the resource group name of the container registry."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the container registry."
  type        = string
}

variable "sku" {
  description = "(Optional) Specifies the tier of the container registry."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "The sku must be Basic, Standard, or Premium."
  }
}

variable "admin_enabled" {
  description = "(Optional) Specifies whether the admin user is enabled."
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "(Required) Specifies the resource id of the Log Analytics workspace used by the diagnostic settings."
  type        = string
}

variable "tags" {
  description = "(Optional) Specifies the resource tags."
  type        = map(string)
  default     = {}
}
