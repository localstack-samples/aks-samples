variable "name" {
  description = "Specifies the name of the Bastion host."
  type        = string
}

variable "public_ip_name" {
  description = "Specifies the name of the public IP address of the Bastion host."
  type        = string
}

variable "location" {
  description = "Specifies the location of the Bastion host and its public IP address."
  type        = string
}

variable "resource_group_name" {
  description = "Specifies the name of the resource group."
  type        = string
}

variable "sku" {
  description = "Specifies the SKU of the Bastion host."
  type        = string
  default     = "Basic"
}

variable "subnet_id" {
  description = "Specifies the resource id of the AzureBastionSubnet subnet."
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
