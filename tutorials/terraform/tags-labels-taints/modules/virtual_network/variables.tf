variable "name" {
  description = "(Required) Specifies the name of the virtual network."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the resource group name of the virtual network."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the virtual network."
  type        = string
}

variable "address_space" {
  description = "(Optional) Specifies the address space of the virtual network."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "system_subnet_name" {
  description = "(Optional) Specifies the name of the subnet hosting the system agent pool nodes."
  type        = string
  default     = "SystemSubnet"
}

variable "system_subnet_address_prefix" {
  description = "(Optional) Specifies the address prefix of the subnet hosting the system agent pool nodes."
  type        = string
  default     = "10.240.0.0/16"
}

variable "user_subnet_name" {
  description = "(Optional) Specifies the name of the subnet hosting the user agent pool nodes."
  type        = string
  default     = "UserSubnet"
}

variable "user_subnet_address_prefix" {
  description = "(Optional) Specifies the address prefix of the subnet hosting the user agent pool nodes."
  type        = string
  default     = "10.241.0.0/16"
}

variable "tags" {
  description = "(Optional) Specifies the resource tags."
  type        = map(string)
  default     = {}
}
