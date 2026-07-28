variable "name" {
  description = "(Required) Specifies the name of the user-assigned managed identity of the AKS cluster."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the resource group name of the user-assigned managed identity."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the user-assigned managed identity."
  type        = string
}

variable "virtual_network_id" {
  description = "(Required) Specifies the resource id of the virtual network the identity gets Network Contributor on."
  type        = string
}

variable "tags" {
  description = "(Optional) Specifies the resource tags."
  type        = map(string)
  default     = {}
}
