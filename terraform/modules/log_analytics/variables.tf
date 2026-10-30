variable "name" {
  description = "Specifies the name of the Log Analytics workspace."
  type        = string
}

variable "location" {
  description = "Specifies the location of the Log Analytics workspace."
  type        = string
}

variable "resource_group_name" {
  description = "Specifies the name of the resource group."
  type        = string
}

variable "sku" {
  description = "Specifies the pricing tier of the Log Analytics workspace."
  type        = string
  default     = "PerGB2018"
}
