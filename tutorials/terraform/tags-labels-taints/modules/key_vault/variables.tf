variable "name" {
  description = "(Required) Specifies the name of the Key Vault (globally unique)."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the resource group name of the Key Vault."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the Key Vault."
  type        = string
}

variable "tenant_id" {
  description = "(Required) Specifies the Azure Active Directory tenant ID used for authenticating requests to the Key Vault."
  type        = string
}

variable "sku_name" {
  description = "(Optional) Specifies the sku name of the Key Vault."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "The sku name must be standard or premium."
  }
}

variable "rbac_authorization_enabled" {
  description = "(Optional) Specifies whether RBAC authorization is enabled for the Key Vault data plane."
  type        = bool
  default     = true
}

variable "purge_protection_enabled" {
  description = "(Optional) Specifies whether purge protection is enabled. Off by default so test vaults can be purged and recreated."
  type        = bool
  default     = false
}

variable "soft_delete_retention_days" {
  description = "(Optional) Specifies the soft delete retention in days."
  type        = number
  default     = 7
}

variable "public_network_access_enabled" {
  description = "(Optional) Specifies whether public network access is enabled."
  type        = bool
  default     = true
}

variable "network_acls_default_action" {
  description = "(Optional) Specifies the default action when no network ACL rules match."
  type        = string
  default     = "Allow"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_acls_default_action)
    error_message = "The network ACLs default action must be Allow or Deny."
  }
}

variable "user_object_id" {
  description = "(Optional) Specifies the object id of a Microsoft Entra ID user to grant Key Vault Administrator on the vault. Empty skips the assignment."
  type        = string
  default     = ""
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
