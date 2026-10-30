variable "name" {
  description = "Specifies the name of the virtual network."
  type        = string
}

variable "location" {
  description = "Specifies the location of the virtual network."
  type        = string
}

variable "resource_group_name" {
  description = "Specifies the name of the resource group."
  type        = string
}

variable "address_prefix" {
  description = "Specifies the address prefix of the virtual network."
  type        = string
  default     = "10.0.0.0/8"
}

variable "system_subnet_name" {
  description = "Specifies the name of the subnet of the system node pool."
  type        = string
  default     = "SystemSubnet"
}

variable "system_subnet_prefix" {
  description = "Specifies the address prefix of the subnet of the system node pool."
  type        = string
  default     = "10.240.0.0/16"
}

variable "user_subnet_name" {
  description = "Specifies the name of the subnet of the user node pool."
  type        = string
  default     = "UserSubnet"
}

variable "user_subnet_prefix" {
  description = "Specifies the address prefix of the subnet of the user node pool."
  type        = string
  default     = "10.241.0.0/16"
}

variable "bastion_subnet_prefix" {
  description = "Specifies the address prefix of the AzureBastionSubnet subnet."
  type        = string
  default     = "10.242.2.0/24"
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
