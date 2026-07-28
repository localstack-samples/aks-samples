variable "name" {
  description = "(Required) Specifies the name of the Log Analytics workspace."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the resource group name of the Log Analytics workspace."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the Log Analytics workspace."
  type        = string
}

variable "sku" {
  description = "(Optional) Specifies the service tier of the workspace."
  type        = string
  default     = "PerGB2018"

  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.sku)
    error_message = "The sku must be Free, Standalone, PerNode, or PerGB2018."
  }
}

variable "retention_in_days" {
  description = "(Optional) Specifies the workspace data retention in days."
  type        = number
  default     = 60
}

variable "tags" {
  description = "(Optional) Specifies the resource tags."
  type        = map(string)
  default     = {}
}
